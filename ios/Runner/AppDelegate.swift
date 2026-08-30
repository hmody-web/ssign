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
    if let registrar = self.registrar(forPlugin: "NativeSystemTabBarPlugin") {
      NativeSystemTabBarPlugin.register(with: registrar)
    }
    DispatchQueue.global(qos: .utility).async {
      try? RouteCache.prime()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
