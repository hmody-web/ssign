import Foundation
import ActivityKit
import UIKit

final class BackgroundDownloadManager: NSObject, URLSessionDownloadDelegate, URLSessionDelegate {
    static let shared = BackgroundDownloadManager()

    struct Record: Codable {
        var id: String
        var appName: String
        var appIconURL: String
        var downloadURL: String
        var fileName: String
        var expectedBytesHint: Int64
        var downloadedBytes: Int64
        var totalBytes: Int64
        var status: String
        var taskIdentifier: Int?
        var localPath: String?
        var iconFileName: String?
        var activityId: String?
        var updatedAt: TimeInterval
    }

    private let queue = DispatchQueue(label: "com.sbooma.sign.background-download.manager")
    private var records: [String: Record] = [:]
    private var lastActivityProgress: [String: Double] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    var eventHandler: (([String: Any]) -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: BoomaShared.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.sharedContainerIdentifier = BoomaShared.appGroup
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        if #available(iOS 13.0, *) {
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
        }
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        loadRecords()
        installCommandObserver()
        _ = session
        reconcileTasks()
        processPendingCommand()
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    func start(id: String, appName: String, appIconURL: String, downloadURL: String, fileName: String, totalBytesHint: Int64) throws -> [String: Any] {
        guard let url = URL(string: downloadURL), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw NSError(domain: "BoomaDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
        }

        if let current = records[id], current.status == "downloading" || current.status == "paused" {
            return dictionary(current)
        }

        // Fail early with a useful error if iOS cannot create the final download folder.
        // This also guarantees that the background task never depends on Dart/Flutter
        // being alive to create its destination directory.
        _ = try downloadsDirectory()

        var record = Record(
            id: id,
            appName: appName,
            appIconURL: appIconURL,
            downloadURL: downloadURL,
            fileName: sanitizedFileName(fileName),
            expectedBytesHint: totalBytesHint,
            downloadedBytes: 0,
            totalBytes: max(totalBytesHint, 0),
            status: "downloading",
            taskIdentifier: nil,
            localPath: nil,
            iconFileName: nil,
            activityId: nil,
            updatedAt: Date().timeIntervalSince1970
        )

        saveIconIfPossible(for: &record)
        let task = session.downloadTask(with: url)
        task.taskDescription = id
        record.taskIdentifier = task.taskIdentifier
        records[id] = record
        persistRecords()
        startLiveActivity(for: id)
        task.resume()
        emit(id)
        return dictionary(records[id] ?? record)
    }

    func pause(id: String) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            guard let task = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.taskDescription == id }) else { return }
            task.cancel(byProducingResumeData: { [weak self] resumeData in
                guard let self else { return }
                self.queue.async {
                    if let resumeData { self.storeResumeData(resumeData, id: id) }
                    guard var record = self.records[id] else { return }
                    record.status = "paused"
                    record.taskIdentifier = nil
                    record.updatedAt = Date().timeIntervalSince1970
                    self.records[id] = record
                    self.persistRecords()
                    self.updateLiveActivity(id: id, force: true)
                    self.emit(id)
                }
            })
        }
    }

    func resume(id: String) {
        queue.async {
            guard var record = self.records[id], record.status == "paused" else { return }
            let task: URLSessionDownloadTask
            if let resumeData = self.loadResumeData(id: id) {
                task = self.session.downloadTask(withResumeData: resumeData)
                self.deleteResumeData(id: id)
            } else if let url = URL(string: record.downloadURL) {
                // Server/resume-data fallback: restart from zero rather than fake resuming.
                record.downloadedBytes = 0
                task = self.session.downloadTask(with: url)
            } else {
                return
            }
            task.taskDescription = id
            record.taskIdentifier = task.taskIdentifier
            record.status = "downloading"
            record.updatedAt = Date().timeIntervalSince1970
            self.records[id] = record
            self.persistRecords()
            task.resume()
            self.updateLiveActivity(id: id, force: true)
            self.emit(id)
        }
    }

    func cancel(id: String) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
            self.queue.async {
                self.deleteResumeData(id: id)
                guard var record = self.records[id] else { return }
                record.status = "cancelled"
                record.taskIdentifier = nil
                record.updatedAt = Date().timeIntervalSince1970
                self.records[id] = record
                self.persistRecords()
                self.updateLiveActivity(id: id, force: true, end: true)
                self.emit(id)
            }
        }
    }

    func allRecords() -> [[String: Any]] {
        queue.sync { records.values.map(dictionary).sorted { ($0["updatedAt"] as? Double ?? 0) > ($1["updatedAt"] as? Double ?? 0) } }
    }

    func attachBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
        _ = session
    }

    private func reconcileTasks() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            self.queue.async {
                for task in tasks {
                    guard let id = task.taskDescription, var record = self.records[id] else { continue }
                    record.taskIdentifier = task.taskIdentifier
                    record.status = task.state == .suspended ? "paused" : "downloading"
                    self.records[id] = record
                }
                self.persistRecords()
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        queue.async {
            guard var record = self.records[id] else { return }
            record.downloadedBytes = max(totalBytesWritten, 0)
            record.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : max(record.expectedBytesHint, record.totalBytes)
            record.status = "downloading"
            record.updatedAt = Date().timeIntervalSince1970
            self.records[id] = record
            self.persistRecords()
            self.updateLiveActivity(id: id)
            self.emit(id)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        queue.sync {
            guard var record = records[id] else { return }
            do {
                let imports = try downloadsDirectory()
                var destination = uniqueDestination(in: imports, fileName: record.fileName)

                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                } catch {
                    // A background URLSession temporary file can occasionally live on a
                    // different volume/container. Fall back to copy + remove rather than
                    // failing the completed download.
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            destination = uniqueDestination(in: imports, fileName: record.fileName)
                        }
                        try FileManager.default.copyItem(at: location, to: destination)
                        try? FileManager.default.removeItem(at: location)
                    } catch {
                        throw NSError(
                            domain: "BoomaDownload",
                            code: 22,
                            userInfo: [NSLocalizedDescriptionKey: "تعذر إنشاء ملف IPA النهائي داخل مجلد Imports: \(error.localizedDescription)"]
                        )
                    }
                }
                let size = ((try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value) ?? record.downloadedBytes
                record.downloadedBytes = size
                record.totalBytes = max(size, record.totalBytes)
                record.localPath = destination.path
                record.status = "completed"
                record.taskIdentifier = nil
                record.updatedAt = Date().timeIntervalSince1970
                records[id] = record
                persistRecords()
                deleteResumeData(id: id)
                updateLiveActivity(id: id, force: true, end: true)
                emit(id)
            } catch {
                markFailed(id: id, message: error.localizedDescription)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled {
            // Pause and explicit cancel are handled by their respective control paths.
            return
        }
        queue.async { self.markFailed(id: id, message: error.localizedDescription) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }

    private func markFailed(id: String, message: String) {
        guard var record = records[id] else { return }
        record.status = "failed"
        record.taskIdentifier = nil
        record.updatedAt = Date().timeIntervalSince1970
        records[id] = record
        persistRecords()
        updateLiveActivity(id: id, force: true, end: true)
        emit(id, error: message)
    }

    private func dictionary(_ record: Record) -> [String: Any] {
        let total = record.totalBytes > 0 ? record.totalBytes : record.expectedBytesHint
        let progress = total > 0 ? min(1, max(0, Double(record.downloadedBytes) / Double(total))) : 0
        return [
            "downloadId": record.id,
            "appName": record.appName,
            "fileName": record.fileName,
            "downloadURL": record.downloadURL,
            "downloadedBytes": record.downloadedBytes,
            "totalBytes": total,
            "progress": progress,
            "status": record.status,
            "paused": record.status == "paused",
            "localPath": record.localPath ?? "",
            "updatedAt": record.updatedAt,
        ]
    }

    private func emit(_ id: String, error: String? = nil) {
        guard let record = records[id] else { return }
        var payload = dictionary(record)
        if let error { payload["error"] = error }
        DispatchQueue.main.async { [weak self] in self?.eventHandler?(payload) }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "paused": return "متوقف مؤقتًا"
        case "completed": return "اكتمل التحميل"
        case "failed": return "فشل التحميل"
        case "cancelled": return "تم إلغاء التحميل"
        default: return "جاري التحميل..."
        }
    }

    private func startLiveActivity(for id: String) {
        guard #available(iOS 16.1, *), ActivityAuthorizationInfo().areActivitiesEnabled, var record = records[id] else { return }
        let attributes = DownloadActivityAttributes(downloadId: id, appName: record.appName, fileName: record.fileName, iconFileName: record.iconFileName)
        let state = DownloadActivityAttributes.ContentState(downloadedBytes: 0, totalBytes: max(record.totalBytes, record.expectedBytesHint), progress: 0, status: "downloading", isPaused: false, statusText: statusText("downloading"))
        do {
            let activity: Activity<DownloadActivityAttributes>
            if #available(iOS 16.2, *) {
                activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            } else {
                activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            }
            record.activityId = activity.id
            records[id] = record
            persistRecords()
        } catch {
            // Download must continue even if Live Activities are disabled/unavailable.
        }
    }

    private func updateLiveActivity(id: String, force: Bool = false, end: Bool = false) {
        guard #available(iOS 16.1, *), let record = records[id] else { return }
        let total = record.totalBytes > 0 ? record.totalBytes : record.expectedBytesHint
        let progress = total > 0 ? min(1, max(0, Double(record.downloadedBytes) / Double(total))) : 0
        if !force {
            let old = lastActivityProgress[id] ?? -1
            if old >= 0 && progress - old < 0.01 { return }
        }
        lastActivityProgress[id] = progress
        let state = DownloadActivityAttributes.ContentState(downloadedBytes: record.downloadedBytes, totalBytes: total, progress: progress, status: record.status, isPaused: record.status == "paused", statusText: statusText(record.status))
        let activities = Activity<DownloadActivityAttributes>.activities.filter { $0.attributes.downloadId == id }
        for activity in activities {
            Task {
                if end {
                    if #available(iOS 16.2, *) {
                        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
                    } else {
                        await activity.end(using: state, dismissalPolicy: .default)
                    }
                } else {
                    if #available(iOS 16.2, *) {
                        await activity.update(ActivityContent(state: state, staleDate: nil))
                    } else {
                        await activity.update(using: state)
                    }
                }
            }
        }
    }


    private func downloadsDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "BoomaDownload",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "تعذر الوصول إلى مجلد Documents الخاص بالتطبيق"]
            )
        }

        let imports = docs.appendingPathComponent("Imports", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: imports,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Write/remove a tiny probe so a broken sandbox or entitlement is reported
            // immediately instead of surfacing later as the vague "Cannot create file".
            let probe = imports.appendingPathComponent(".booma-write-test")
            try Data([0x42]).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return imports
        } catch {
            throw NSError(
                domain: "BoomaDownload",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "تعذر إنشاء مجلد التنزيل أو الكتابة داخله: \(error.localizedDescription)"]
            )
        }
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        var destination = directory.appendingPathComponent(sanitizedFileName(fileName))
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let ext = destination.pathExtension
        let stem = destination.deletingPathExtension().lastPathComponent
        var counter = 1
        repeat {
            let suffix = "\(Int(Date().timeIntervalSince1970))-\(counter)"
            let name = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            destination = directory.appendingPathComponent(name)
            counter += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    private func saveIconIfPossible(for record: inout Record) {
        guard !record.appIconURL.isEmpty,
              let source = URL(string: record.appIconURL),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BoomaShared.appGroup) else { return }
        let fileName = "download-icon-\(record.id.replacingOccurrences(of: "/", with: "_"))\(source.pathExtension.isEmpty ? ".img" : ".\(source.pathExtension)")"
        let dest = container.appendingPathComponent(fileName)
        record.iconFileName = fileName
        URLSession.shared.dataTask(with: source) { data, _, _ in
            if let data { try? data.write(to: dest, options: .atomic) }
        }.resume()
    }

    private func sanitizedFileName(_ input: String) -> String {
        let fallback = "Application-\(Int(Date().timeIntervalSince1970)).ipa"
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = fallback }
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r\t").union(.controlCharacters)
        value = value.components(separatedBy: invalid).joined(separator: "-")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = fallback }
        if !value.lowercased().hasSuffix(".ipa") { value += ".ipa" }
        return value
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: BoomaShared.appGroup) }

    private func loadRecords() {
        guard let data = defaults?.data(forKey: "backgroundDownloadRecords"), let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
        records = decoded
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: "backgroundDownloadRecords")
    }

    private func resumeDataURL(id: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BoomaShared.appGroup)?.appendingPathComponent("resume-\(id.replacingOccurrences(of: "/", with: "_"))")
    }
    private func storeResumeData(_ data: Data, id: String) { if let url = resumeDataURL(id: id) { try? data.write(to: url, options: .atomic) } }
    private func loadResumeData(id: String) -> Data? { resumeDataURL(id: id).flatMap { try? Data(contentsOf: $0) } }
    private func deleteResumeData(id: String) { if let url = resumeDataURL(id: id) { try? FileManager.default.removeItem(at: url) } }

    private func installCommandObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let manager = Unmanaged<BackgroundDownloadManager>.fromOpaque(observer).takeUnretainedValue()
            manager.processPendingCommand()
        }, BoomaShared.commandNotification as CFString, nil, .deliverImmediately)
    }

    private func processPendingCommand() {
        guard let command = defaults?.dictionary(forKey: "pendingDownloadCommand"),
              let id = command["downloadId"] as? String,
              let action = command["action"] as? String else { return }
        defaults?.removeObject(forKey: "pendingDownloadCommand")
        if action == "pause" { pause(id: id) }
        if action == "resume" { resume(id: id) }
    }
}
