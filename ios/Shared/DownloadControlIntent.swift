import Foundation
import AppIntents

@available(iOS 17.0, *)
struct DownloadControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Download control"
    static var description = IntentDescription("Pause or resume a background download.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Download ID")
    var downloadId: String

    @Parameter(title: "Action")
    var action: String

    init() {
        downloadId = ""
        action = ""
    }

    init(downloadId: String, action: String) {
        self.downloadId = downloadId
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        guard !downloadId.isEmpty, action == "pause" || action == "resume" else {
            return .result()
        }
        let defaults = UserDefaults(suiteName: BoomaShared.appGroup)
        defaults?.set([
            "downloadId": downloadId,
            "action": action,
            "createdAt": Date().timeIntervalSince1970,
        ], forKey: "pendingDownloadCommand")
        defaults?.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(BoomaShared.commandNotification as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
