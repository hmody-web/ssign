import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var appInfoChannel: FlutterMethodChannel?
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "SignNativePlugin") {
      SignNativePlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "AdminSecurePlugin") {
      AdminSecurePlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "NativeSystemTabBarPlugin") {
      NativeSystemTabBarPlugin.register(with: registrar)
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      appInfoChannel = FlutterMethodChannel(name: "booma/app_info", binaryMessenger: controller.binaryMessenger)
      appInfoChannel?.setMethodCallHandler { call, result in
        guard call.method == "current" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let info = Bundle.main.infoDictionary ?? [:]
        result([
          "version": info["CFBundleShortVersionString"] as? String ?? "",
          "build": info["CFBundleVersion"] as? String ?? ""
        ])
      }
    }
    DispatchQueue.global(qos: .utility).async {
      try? RouteCache.prime()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
