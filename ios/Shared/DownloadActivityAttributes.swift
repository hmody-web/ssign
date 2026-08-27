import Foundation
import ActivityKit

@available(iOS 16.1, *)
struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var downloadedBytes: Int64
        var totalBytes: Int64
        var progress: Double
        var status: String
        var isPaused: Bool
        var statusText: String
    }

    var downloadId: String
    var appName: String
    var fileName: String
    var iconFileName: String?
}

enum BoomaShared {
    static let appGroup = "group.com.sbooma.sign"
    static let backgroundSessionIdentifier = "com.sbooma.sign.background-downloads"
    static let commandNotification = "com.sbooma.sign.download-command"
}
