import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "SignNativePlugin") {
      SignNativePlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "AdminSecurePlugin") {
      AdminSecurePlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "BackgroundDownloadPlugin") {
      BackgroundDownloadPlugin.register(with: registrar)
    }
    _ = BackgroundDownloadManager.shared
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    if identifier == BoomaShared.backgroundSessionIdentifier {
      BackgroundDownloadManager.shared.attachBackgroundCompletionHandler(completionHandler)
      return
    }
    super.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
  }
}
