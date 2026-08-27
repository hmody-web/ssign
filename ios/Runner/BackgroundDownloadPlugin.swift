import Flutter
import UIKit

final class BackgroundDownloadPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BackgroundDownloadPlugin()
        let methods = FlutterMethodChannel(name: "booma.background_download/methods", binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(name: "booma.background_download/events", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        events.setStreamHandler(instance)
        BackgroundDownloadManager.shared.eventHandler = { [weak instance] payload in instance?.sink?(payload) }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start":
            do {
                let payload = try BackgroundDownloadManager.shared.start(
                    id: args["downloadId"] as? String ?? UUID().uuidString,
                    appName: args["appName"] as? String ?? "Application",
                    appIconURL: args["appIcon"] as? String ?? "",
                    downloadURL: args["downloadURL"] as? String ?? "",
                    fileName: args["fileName"] as? String ?? "Application.ipa",
                    totalBytesHint: (args["totalBytes"] as? NSNumber)?.int64Value ?? 0
                )
                result(payload)
            } catch {
                result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
            }
        case "pause":
            if let id = args["downloadId"] as? String { BackgroundDownloadManager.shared.pause(id: id) }
            result(nil)
        case "resume":
            if let id = args["downloadId"] as? String { BackgroundDownloadManager.shared.resume(id: id) }
            result(nil)
        case "cancel":
            if let id = args["downloadId"] as? String { BackgroundDownloadManager.shared.cancel(id: id) }
            result(nil)
        case "list":
            result(BackgroundDownloadManager.shared.allRecords())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        BackgroundDownloadManager.shared.eventHandler = { [weak self] payload in self?.sink?(payload) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
