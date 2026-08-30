import Flutter
import UIKit

/// Bridges a real UIKit UITabBar into Flutter.
///
/// There is intentionally no hand-made blur/glass styling here. When the app is
/// built with a current iOS SDK, UIKit owns the visual treatment (including the
/// system Liquid Glass appearance on supported iOS versions).
final class NativeSystemTabBarPlugin: NSObject, FlutterPlugin {
    static let channelName = "booma/native_system_tab_bar_channel"
    static let viewType = "booma/native_system_tab_bar"

    private static var channel: FlutterMethodChannel?
    fileprivate static weak var activeView: NativeSystemTabBarView?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = NativeSystemTabBarPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            NativeSystemTabBarFactory(messenger: registrar.messenger()),
            withId: viewType
        )
        self.channel = channel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setSelectedIndex":
            guard let value = call.arguments as? Int else {
                result(FlutterError(code: "bad_index", message: "Expected an integer tab index.", details: nil))
                return
            }
            DispatchQueue.main.async {
                NativeSystemTabBarPlugin.activeView?.setSelectedIndex(value)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    fileprivate static func notifyFlutter(selectedIndex: Int) {
        channel?.invokeMethod("onTabSelected", arguments: selectedIndex)
    }
}

private final class NativeSystemTabBarFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        NativeSystemTabBarView(frame: frame, viewId: viewId, arguments: args)
    }
}

fileprivate final class NativeSystemTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
    private let rootView: UIView
    private let tabBar: UITabBar

    init(frame: CGRect, viewId: Int64, arguments args: Any?) {
        rootView = UIView(frame: frame)
        tabBar = UITabBar(frame: frame)
        super.init()

        rootView.backgroundColor = .clear
        rootView.isOpaque = false

        tabBar.delegate = self
        tabBar.isTranslucent = true
        tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabBar.frame = rootView.bounds

        let params = args as? [String: Any]
        let isArabic = params?["isArabic"] as? Bool ?? true
        let selectedIndex = params?["selectedIndex"] as? Int ?? 0

        rootView.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight
        tabBar.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight

        let titles: [String]
        if isArabic {
            titles = ["بــومـة", "الملفات", "التوقيع", "الإعدادات"]
        } else {
            titles = ["Booma", "Files", "Sign", "Settings"]
        }

        let symbols = [
            ("square.grid.2x2", "square.grid.2x2.fill"),
            ("folder", "folder.fill"),
            ("signature", "signature"),
            ("gearshape", "gearshape.fill")
        ]

        tabBar.items = zip(titles, symbols).enumerated().map { index, pair in
            let (title, symbolPair) = pair
            let item = UITabBarItem(
                title: title,
                image: UIImage(systemName: symbolPair.0),
                selectedImage: UIImage(systemName: symbolPair.1)
            )
            item.tag = index
            return item
        }

        rootView.addSubview(tabBar)
        setSelectedIndex(selectedIndex)
        NativeSystemTabBarPlugin.activeView = self
    }

    func view() -> UIView {
        rootView
    }

    func setSelectedIndex(_ index: Int) {
        guard let items = tabBar.items, items.indices.contains(index) else { return }
        tabBar.selectedItem = items[index]
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        NativeSystemTabBarPlugin.notifyFlutter(selectedIndex: item.tag)
    }
}
