import Flutter
import UIKit
import SwiftUI


private final class BoomaImageCache {
    static let shared = BoomaImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var timestamps: [String: Date] = [:]
    private let queue = DispatchQueue(label: "booma.image.cache")
    private let ttl: TimeInterval = 300

    func image(for key: String) -> UIImage? {
        guard let image = cache.object(forKey: key as NSString) else { return nil }
        let fresh = queue.sync { Date().timeIntervalSince(timestamps[key] ?? .distantPast) < ttl }
        if fresh { return image }
        cache.removeObject(forKey: key as NSString)
        queue.async { self.timestamps.removeValue(forKey: key) }
        return nil
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
        queue.async { self.timestamps[key] = Date() }
    }
}

/// Bridges a real UIKit UITabBar into Flutter.
///
/// There is intentionally no hand-made blur/glass styling here. When the app is
/// built with a current iOS SDK, UIKit owns the visual treatment (including the
/// system Liquid Glass appearance on supported iOS versions).
final class NativeSystemTabBarPlugin: NSObject, FlutterPlugin {
    static let channelName = "booma/native_system_tab_bar_channel"
    static let viewType = "booma/native_system_tab_bar"
    static let appSheetChannelName = "booma/native_app_sheet_channel"

    private static var channel: FlutterMethodChannel?
    private static var appSheetChannel: FlutterMethodChannel?
    fileprivate static weak var activeView: NativeSystemTabBarView?
    @available(iOS 15.0, *) fileprivate static var activeAppSheetModel: NativeAppSheetStateModel?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = NativeSystemTabBarPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let appSheetChannel = FlutterMethodChannel(name: appSheetChannelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: appSheetChannel)
        registrar.register(
            NativeSystemTabBarFactory(messenger: registrar.messenger()),
            withId: viewType
        )
        registerNativeControls(with: registrar)
        self.channel = channel
        self.appSheetChannel = appSheetChannel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setSelectedIndex":
            guard let value = call.arguments as? Int else {
                result(FlutterError(code: "bad_index", message: "Expected an integer tab index.", details: nil))
                return
            }
            DispatchQueue.main.async { NativeSystemTabBarPlugin.activeView?.setSelectedIndex(value) }
            result(nil)
        case "presentAppSheet":
            guard let payload = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_payload", message: "Expected app sheet payload.", details: nil)); return
            }
            DispatchQueue.main.async { NativeSystemTabBarPlugin.presentAppSheet(payload) }
            result(nil)
        case "updateAppSheetState":
            guard let next = call.arguments as? [String: Any] else { result(nil); return }
            if #available(iOS 15.0, *) {
                DispatchQueue.main.async { NativeSystemTabBarPlugin.activeAppSheetModel?.update(next) }
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    fileprivate static func presentAppSheet(_ payload: [String: Any]) {
        guard let presenter = topViewController() else { return }
        let app = payload["app"] as? [String: Any] ?? [:]
        let state = payload["state"] as? [String: Any] ?? [:]
        let isArabic = payload["isArabic"] as? Bool ?? false
        let isDark = payload["isDark"] as? Bool ?? true
        let model = NativeAppSheetStateModel(state: state)
        activeAppSheetModel = model
        let view = NativeAppSheetSwiftUIView(app: app, model: model, isArabic: isArabic, isDark: isDark) { action, value in
            var args: [String: Any] = ["id": app["id"] as? String ?? "", "action": action]
            if let value { args["value"] = value }
            appSheetChannel?.invokeMethod("action", arguments: args)
        }
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = isDark ? .dark : .light
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        presenter.present(host, animated: true)
    }

    private static func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }.first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
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

// MARK: - Reusable native iOS controls

private enum NativeControlNames {
    static let button = "booma/native_system_button"
    static let textField = "booma/native_system_text_field"
    static let categories = "booma/native_system_categories"
    static let appCard = "booma/native_app_card"
    static let featuredBanner = "booma/native_featured_banner"
}

extension NativeSystemTabBarPlugin {
    static func registerNativeControls(with registrar: FlutterPluginRegistrar) {
        registrar.register(NativeSystemButtonFactory(messenger: registrar.messenger()), withId: NativeControlNames.button)
        registrar.register(NativeSystemTextFieldFactory(messenger: registrar.messenger()), withId: NativeControlNames.textField)
        registrar.register(NativeSystemCategoriesFactory(messenger: registrar.messenger()), withId: NativeControlNames.categories)
        registrar.register(NativeAppCardFactory(messenger: registrar.messenger()), withId: NativeControlNames.appCard)
        registrar.register(NativeFeaturedBannerFactory(messenger: registrar.messenger()), withId: NativeControlNames.featuredBanner)
    }
}

private final class NativeControlBridge: NSObject {
    let channel: FlutterMethodChannel
    init(messenger: FlutterBinaryMessenger, viewId: Int64) {
        channel = FlutterMethodChannel(name: "booma/native_control/\(viewId)", binaryMessenger: messenger)
        super.init()
    }
}

private final class NativeSystemButtonFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeSystemButtonView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

private final class NativeSystemButtonView: NSObject, FlutterPlatformView {
    let button: UIButton
    let bridge: NativeControlBridge

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        button = UIButton(type: .system)
        super.init()
        let p = args as? [String: Any] ?? [:]
        let title = p["title"] as? String ?? ""
        let imageName = p["systemImage"] as? String
        let prominent = p["prominent"] as? Bool ?? false
        let destructive = p["destructive"] as? Bool ?? false
        let enabled = p["enabled"] as? Bool ?? true

        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = prominent ? .prominentGlass() : .glass()
        } else {
            configuration = prominent ? .filled() : .tinted()
        }
        configuration.title = title
        if let imageName, !imageName.isEmpty { configuration.image = UIImage(systemName: imageName) }
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.tintColor = destructive ? .systemRed : nil
        button.isEnabled = enabled
        button.frame = frame
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @objc private func tapped() { bridge.channel.invokeMethod("tap", arguments: nil) }
    func view() -> UIView { button }
}

private final class NativeSystemTextFieldFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeSystemTextFieldView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

private final class NativeSystemTextFieldView: NSObject, FlutterPlatformView, UITextFieldDelegate {
    let root = UIView()
    let field = UITextField()
    let bridge: NativeControlBridge

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        super.init()
        let p = args as? [String: Any] ?? [:]
        root.frame = frame
        root.backgroundColor = .clear
        field.frame = root.bounds
        field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        field.text = p["text"] as? String ?? ""
        field.placeholder = p["placeholder"] as? String ?? ""
        field.isSecureTextEntry = p["obscure"] as? Bool ?? false
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .search
        field.delegate = self
        field.addTarget(self, action: #selector(changed), for: .editingChanged)
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true

        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect()
            let effectView = UIVisualEffectView(effect: effect)
            effectView.frame = root.bounds
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            effectView.layer.cornerRadius = 18
            effectView.clipsToBounds = true
            root.addSubview(effectView)
        } else {
            let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            effectView.frame = root.bounds
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            effectView.layer.cornerRadius = 14
            effectView.clipsToBounds = true
            root.addSubview(effectView)
        }

        if let imageName = p["leadingSystemImage"] as? String, !imageName.isEmpty {
            let image = UIImageView(image: UIImage(systemName: imageName))
            image.tintColor = .secondaryLabel
            image.contentMode = .scaleAspectFit
            image.frame = CGRect(x: 10, y: 0, width: 22, height: max(frame.height, 44))
            let holder = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: max(frame.height, 44)))
            holder.addSubview(image)
            field.leftView = holder
            field.leftViewMode = .always
        } else {
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
            field.leftViewMode = .always
        }
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        field.rightViewMode = .always
        root.addSubview(field)

        bridge.channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            if call.method == "setText" {
                self.field.text = call.arguments as? String ?? ""
                result(nil)
            } else { result(FlutterMethodNotImplemented) }
        }

        if p["autofocus"] as? Bool == true {
            DispatchQueue.main.async { [weak self] in self?.field.becomeFirstResponder() }
        }
    }

    @objc private func changed() { bridge.channel.invokeMethod("changed", arguments: field.text ?? "") }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        bridge.channel.invokeMethod("submitted", arguments: textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
    func view() -> UIView { root }
}

private final class NativeSystemCategoriesFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeSystemCategoriesView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

private final class NativeSystemCategoriesView: NSObject, FlutterPlatformView {
    let root = UIView()
    let scroll = UIScrollView()
    let stack = UIStackView()
    let bridge: NativeControlBridge
    let selected: String?
    let isArabic: Bool
    var values: [String] = []

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        let p = args as? [String: Any] ?? [:]
        selected = p["selected"] as? String
        isArabic = p["isArabic"] as? Bool ?? true
        super.init()
        values = p["values"] as? [String] ?? []
        let labels = p["labels"] as? [String] ?? values

        root.frame = frame
        root.backgroundColor = .clear
        root.clipsToBounds = true
        root.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight

        scroll.frame = root.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.alwaysBounceVertical = false
        scroll.isDirectionalLockEnabled = true
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight

        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight
        scroll.addSubview(stack)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        if isArabic {
            for (i, value) in values.enumerated().reversed() {
                let supplied = i < labels.count ? labels[i] : value
                addButton(title: categoryLabel(raw: value, supplied: supplied), value: value, selected: value == self.selected)
            }
            addButton(title: "الكل", value: "", selected: self.selected == nil || self.selected?.isEmpty == true)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.root.layoutIfNeeded()
                let x = max(0, self.scroll.contentSize.width - self.scroll.bounds.width)
                self.scroll.setContentOffset(CGPoint(x: x, y: 0), animated: false)
            }
        } else {
            addButton(title: "All", value: "", selected: self.selected == nil || self.selected?.isEmpty == true)
            for (i, value) in values.enumerated() {
                let supplied = i < labels.count ? labels[i] : value
                addButton(title: categoryLabel(raw: value, supplied: supplied), value: value, selected: value == self.selected)
            }
        }
    }

    private func categoryLabel(raw: String, supplied: String) -> String {
        guard isArabic else { return supplied }
        // Keep Dart-provided Arabic labels, but also translate here so the native
        // row can never fall back to English while the app language is Arabic.
        if supplied.range(of: "[\\u{0600}-\\u{06FF}]", options: .regularExpression) != nil { return supplied }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: String] = [
            "games":"ألعاب", "game":"ألعاب", "social":"تواصل اجتماعي", "social networking":"تواصل اجتماعي",
            "photo & video":"صور وفيديو", "photo":"صور", "video":"فيديو", "music":"موسيقى", "entertainment":"ترفيه",
            "utilities":"أدوات", "utility":"أدوات", "tools":"أدوات", "business":"أعمال", "education":"تعليم",
            "productivity":"إنتاجية", "finance":"مال وأعمال", "shopping":"تسوق", "lifestyle":"نمط حياة",
            "health & fitness":"صحة ولياقة", "health":"صحة ولياقة", "sports":"رياضة", "travel":"سفر",
            "navigation":"ملاحة", "news":"أخبار", "weather":"طقس", "food & drink":"طعام وشراب", "food":"طعام وشراب",
            "books":"كتب", "reference":"مراجع", "medical":"طب", "developer tools":"أدوات المطور",
            "graphics & design":"رسوم وتصميم"
        ]
        return map[key] ?? supplied
    }

    private func addButton(title: String, value: String, selected isSelected: Bool) {
        let b = UIButton(type: .system)
        var c: UIButton.Configuration
        if #available(iOS 26.0, *) { c = isSelected ? .prominentGlass() : .glass() }
        else { c = isSelected ? .filled() : .tinted() }
        c.title = title
        c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        b.configuration = c
        b.accessibilityIdentifier = value
        b.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight
        b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        stack.addArrangedSubview(b)
    }
    @objc private func tapped(_ sender: UIButton) { bridge.channel.invokeMethod("selected", arguments: sender.accessibilityIdentifier ?? "") }
    func view() -> UIView { root }
}

private final class NativeAppCardFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeAppCardView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

private final class NativeAppCardView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate {
    let root = UIView()
    let bridge: NativeControlBridge
    let action = UIButton(type: .system)
    let downloadTrackLayer = CAShapeLayer()
    let downloadProgressLayer = CAShapeLayer()
    let isArabic: Bool

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        let p = args as? [String: Any] ?? [:]
        let app = p["app"] as? [String: Any] ?? [:]
        let state = p["state"] as? [String: Any] ?? [:]
        isArabic = p["isArabic"] as? Bool ?? true
        super.init()

        root.frame = frame
        root.backgroundColor = .clear
        root.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight

        let background: UIVisualEffectView
        if #available(iOS 26.0, *) { background = UIVisualEffectView(effect: UIGlassEffect()) }
        else { background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial)) }
        background.isUserInteractionEnabled = false
        background.layer.cornerRadius = 20
        background.clipsToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(background)

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFill
        icon.layer.cornerRadius = 15
        icon.clipsToBounds = true
        icon.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        root.addSubview(icon)
        loadImage(app["iconUrl"] as? String, into: icon)

        let name = UILabel()
        name.font = .preferredFont(forTextStyle: .headline)
        name.adjustsFontForContentSizeCategory = true
        name.text = app["displayName"] as? String ?? app["name"] as? String ?? ""
        name.numberOfLines = 1
        name.textAlignment = isArabic ? .right : .left

        let subtitle = UILabel()
        subtitle.font = .preferredFont(forTextStyle: .caption1)
        subtitle.textColor = .secondaryLabel
        subtitle.text = app["displaySubtitle"] as? String ?? ""
        subtitle.numberOfLines = 1
        subtitle.textAlignment = isArabic ? .right : .left

        let meta = UILabel()
        meta.font = .preferredFont(forTextStyle: .caption2)
        meta.textColor = .tertiaryLabel
        meta.text = app["meta"] as? String ?? ""
        meta.numberOfLines = 1
        meta.textAlignment = isArabic ? .right : .left

        let labels = UIStackView(arrangedSubviews: [name, subtitle, meta])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.isUserInteractionEnabled = false
        root.addSubview(labels)

        action.translatesAutoresizingMaskIntoConstraints = false
        action.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        root.addSubview(action)
        downloadTrackLayer.fillColor = UIColor.clear.cgColor
        downloadTrackLayer.strokeColor = UIColor.tertiaryLabel.withAlphaComponent(0.32).cgColor
        downloadTrackLayer.lineWidth = 2.6
        downloadTrackLayer.lineCap = .round
        downloadTrackLayer.isHidden = true
        action.layer.addSublayer(downloadTrackLayer)

        downloadProgressLayer.fillColor = UIColor.clear.cgColor
        downloadProgressLayer.strokeColor = UIColor.label.cgColor
        downloadProgressLayer.lineWidth = 2.6
        downloadProgressLayer.lineCap = .round
        downloadProgressLayer.strokeEnd = 0
        downloadProgressLayer.isHidden = true
        action.layer.addSublayer(downloadProgressLayer)
        applyState(state)

        if isArabic {
            NSLayoutConstraint.activate([
                background.leadingAnchor.constraint(equalTo: root.leadingAnchor), background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                background.topAnchor.constraint(equalTo: root.topAnchor), background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                icon.rightAnchor.constraint(equalTo: root.rightAnchor, constant: -12), icon.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 62), icon.heightAnchor.constraint(equalToConstant: 62),
                action.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 12), action.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                action.widthAnchor.constraint(greaterThanOrEqualToConstant: 88), action.heightAnchor.constraint(equalToConstant: 40),
                labels.rightAnchor.constraint(equalTo: icon.leftAnchor, constant: -12),
                labels.leftAnchor.constraint(greaterThanOrEqualTo: action.rightAnchor, constant: 10),
                labels.centerYAnchor.constraint(equalTo: root.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                background.leadingAnchor.constraint(equalTo: root.leadingAnchor), background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                background.topAnchor.constraint(equalTo: root.topAnchor), background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                icon.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 12), icon.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 62), icon.heightAnchor.constraint(equalToConstant: 62),
                action.rightAnchor.constraint(equalTo: root.rightAnchor, constant: -12), action.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                action.widthAnchor.constraint(greaterThanOrEqualToConstant: 72), action.heightAnchor.constraint(equalToConstant: 40),
                labels.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 12),
                labels.rightAnchor.constraint(lessThanOrEqualTo: action.leftAnchor, constant: -10),
                labels.centerYAnchor.constraint(equalTo: root.centerYAnchor)
            ])
        }

        bridge.channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            if call.method == "updateState", let next = call.arguments as? [String: Any] {
                DispatchQueue.main.async { self.applyState(next) }
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        root.addGestureRecognizer(tap)
    }

    private func applyState(_ state: [String: Any]) {
        let downloading = state["downloading"] as? Bool ?? false
        let paused = state["paused"] as? Bool ?? false
        let hasFile = state["hasFile"] as? Bool ?? false
        let stage = state["stage"] as? String ?? ""
        let progress: CGFloat = {
            if let d = state["progress"] as? Double { return CGFloat(max(0, min(1, d))) }
            if let n = state["progress"] as? NSNumber { return CGFloat(max(0, min(1, n.doubleValue))) }
            return 0
        }()

        var config: UIButton.Configuration
        if downloading {
            config = .plain()
            config.title = nil
            config.image = UIImage(systemName: paused ? "play.fill" : "stop.fill")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            config.baseForegroundColor = .label
            action.accessibilityIdentifier = "pause"
            action.isEnabled = true
            updateProgressRing(progress: progress, visible: true)
        } else if stage == "signing" || stage == "installing" {
            config = .gray()
            config.title = stage == "signing" ? (isArabic ? "جارٍ التوقيع" : "Signing…") : (isArabic ? "جارٍ التثبيت" : "Installing…")
            config.image = nil
            action.isEnabled = false
            updateProgressRing(progress: 0, visible: false)
        } else if hasFile {
            config = .gray()
            config.title = isArabic ? "توقيع" : "Sign"
            config.image = nil
            action.accessibilityIdentifier = "sign"
            action.isEnabled = true
            updateProgressRing(progress: 0, visible: false)
        } else {
            if #available(iOS 26.0, *) { config = .prominentGlass() } else { config = .filled() }
            config.title = isArabic ? "تنزيل" : "GET"
            config.image = nil
            action.accessibilityIdentifier = "download"
            action.isEnabled = true
            updateProgressRing(progress: 0, visible: false)
        }
        config.cornerStyle = .capsule
        action.configuration = config
    }

    private func updateProgressRing(progress: CGFloat, visible: Bool) {
        downloadTrackLayer.isHidden = !visible
        downloadProgressLayer.isHidden = !visible
        guard visible else { downloadProgressLayer.strokeEnd = 0; return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.action.layoutIfNeeded()
            let diameter: CGFloat = 34
            let rect = CGRect(
                x: (self.action.bounds.width - diameter) / 2,
                y: (self.action.bounds.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            let path = UIBezierPath(ovalIn: rect).cgPath
            self.downloadTrackLayer.frame = self.action.bounds
            self.downloadProgressLayer.frame = self.action.bounds
            self.downloadTrackLayer.path = path
            self.downloadProgressLayer.path = path

            let current = self.downloadProgressLayer.presentation()?.strokeEnd ?? self.downloadProgressLayer.strokeEnd
            self.downloadProgressLayer.removeAnimation(forKey: "progress")
            self.downloadProgressLayer.strokeEnd = progress
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = current
            animation.toValue = progress
            animation.duration = 0.18
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.downloadProgressLayer.add(animation, forKey: "progress")
        }
    }

    private func loadImage(_ raw: String?, into view: UIImageView) {
        guard let raw, let url = URL(string: raw), !raw.isEmpty else { view.image = UIImage(systemName: "app.fill"); return }
        if let cached = BoomaImageCache.shared.image(for: raw) { view.image = cached; return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            BoomaImageCache.shared.store(image, for: raw)
            DispatchQueue.main.async { view.image = image }
        }.resume()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v: UIView? = touch.view
        while let current = v {
            if current === action { return false }
            v = current.superview
        }
        return true
    }

    @objc private func cardTapped() { bridge.channel.invokeMethod("tap", arguments: nil) }
    @objc private func actionTapped(_ sender: UIButton) { bridge.channel.invokeMethod(sender.accessibilityIdentifier ?? "download", arguments: nil) }
    func view() -> UIView { root }
}

private final class NativeFeaturedBannerFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeFeaturedBannerView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

private final class NativeFeaturedBannerView: NSObject, FlutterPlatformView {
    let root = UIControl()
    let bridge: NativeControlBridge
    var imageURLs: [String] = []
    var imageIndex = 0
    weak var backgroundImage: UIImageView?
    var timer: Timer?

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        super.init()
        let p = args as? [String: Any] ?? [:]
        let app = p["app"] as? [String: Any] ?? [:]
        let isArabic = p["isArabic"] as? Bool ?? true
        imageURLs = app["screenshots"] as? [String] ?? []

        root.frame = frame
        root.backgroundColor = .secondarySystemBackground
        root.layer.cornerRadius = 24
        root.clipsToBounds = true
        root.semanticContentAttribute = isArabic ? .forceRightToLeft : .forceLeftToRight
        root.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        let bg = UIImageView(frame: root.bounds)
        bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bg.contentMode = .scaleAspectFill
        bg.backgroundColor = .black
        bg.isUserInteractionEnabled = false
        root.addSubview(bg)
        backgroundImage = bg
        loadBannerImage()

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.alpha = 0.66
        blur.isUserInteractionEnabled = false
        root.addSubview(blur)
        let shade = UIView()
        shade.translatesAutoresizingMaskIntoConstraints = false
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.11)
        shade.isUserInteractionEnabled = false
        root.addSubview(shade)

        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFill
        icon.layer.cornerRadius = 15
        icon.clipsToBounds = true
        icon.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        loadRemoteImage(app["iconUrl"] as? String, into: icon)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = app["displayName"] as? String ?? ""
        title.font = .preferredFont(forTextStyle: .title2)
        title.textColor = .white
        title.numberOfLines = 2
        title.textAlignment = isArabic ? .right : .left

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = app["displaySubtitle"] as? String ?? ""
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.82)
        subtitle.numberOfLines = 3
        subtitle.textAlignment = isArabic ? .right : .left

        let version = UIButton(type: .system)
        version.translatesAutoresizingMaskIntoConstraints = false
        var vc: UIButton.Configuration
        if #available(iOS 26.0, *) { vc = .glass() } else { vc = .tinted() }
        vc.title = ((app["version"] as? String)?.isEmpty == false) ? "v\(app["version"] as? String ?? "")" : (isArabic ? "جديد" : "New")
        vc.cornerStyle = .capsule
        version.configuration = vc
        version.tintColor = .white
        version.isUserInteractionEnabled = false

        root.addSubview(icon); root.addSubview(title); root.addSubview(subtitle); root.addSubview(version)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: root.leadingAnchor), blur.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            blur.topAnchor.constraint(equalTo: root.topAnchor), blur.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            shade.leadingAnchor.constraint(equalTo: root.leadingAnchor), shade.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shade.topAnchor.constraint(equalTo: root.topAnchor), shade.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 62), icon.heightAnchor.constraint(equalToConstant: 62),
            title.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.53),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.60),
            version.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        if isArabic {
            NSLayoutConstraint.activate([
                icon.rightAnchor.constraint(equalTo: root.rightAnchor, constant: -20), icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
                title.rightAnchor.constraint(equalTo: icon.leftAnchor, constant: -14), title.leftAnchor.constraint(greaterThanOrEqualTo: root.leftAnchor, constant: 20), title.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
                subtitle.rightAnchor.constraint(equalTo: icon.leftAnchor, constant: -14), subtitle.leftAnchor.constraint(greaterThanOrEqualTo: root.leftAnchor, constant: 20), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
                version.rightAnchor.constraint(equalTo: icon.leftAnchor, constant: -14), version.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14)
            ])
        } else {
            NSLayoutConstraint.activate([
                icon.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20), icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
                title.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 14), title.rightAnchor.constraint(lessThanOrEqualTo: root.rightAnchor, constant: -20), title.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
                subtitle.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 14), subtitle.rightAnchor.constraint(lessThanOrEqualTo: root.rightAnchor, constant: -20), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
                version.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 14), version.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14)
            ])
        }

        if imageURLs.count > 1 {
            timer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.imageIndex = (self.imageIndex + 1) % self.imageURLs.count
                self.loadBannerImage(animated: true)
            }
        }
    }

    deinit { timer?.invalidate() }

    private func loadBannerImage(animated: Bool = false) {
        guard !imageURLs.isEmpty, let url = URL(string: imageURLs[imageIndex]) else { return }
        let key = imageURLs[imageIndex]
        if let cached = BoomaImageCache.shared.image(for: key) {
            backgroundImage?.image = cached
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = UIImage(data: data) else { return }
            BoomaImageCache.shared.store(image, for: key)
            DispatchQueue.main.async {
                guard let view = self.backgroundImage else { return }
                if animated { UIView.transition(with: view, duration: 0.45, options: .transitionCrossDissolve) { view.image = image } }
                else { view.image = image }
            }
        }.resume()
    }
    private func loadRemoteImage(_ raw: String?, into view: UIImageView) {
        view.image = UIImage(named: "NoIcon")
        guard let raw, let url = URL(string: raw), !raw.isEmpty else { return }
        if let cached = BoomaImageCache.shared.image(for: raw) { view.image = cached; return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            BoomaImageCache.shared.store(image, for: raw)
            DispatchQueue.main.async { view.image = image }
        }.resume()
    }
    @objc private func tapped() { bridge.channel.invokeMethod("tap", arguments: nil) }
    func view() -> UIView { root }
}

@available(iOS 15.0, *)
fileprivate final class NativeAppSheetStateModel: ObservableObject {
    @Published var state: [String: Any]
    init(state: [String: Any]) { self.state = state }
    func update(_ next: [String: Any]) {
        if let incomingId = next["id"] as? String, let currentId = state["id"] as? String, !currentId.isEmpty, incomingId != currentId { return }
        var merged = state
        for (key, value) in next { merged[key] = value }
        state = merged
    }
}

@available(iOS 15.0, *)
private struct BoomaCachedRemoteImage: View {
    let raw: String
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var loading = true

    init(_ raw: String, contentMode: ContentMode = .fill) {
        self.raw = raw
        self.contentMode = contentMode
        _image = State(initialValue: BoomaImageCache.shared.image(for: raw))
        _loading = State(initialValue: BoomaImageCache.shared.image(for: raw) == nil)
    }

    var body: some View {
        ZStack {
            Image("NoIcon")
                .resizable()
                .aspectRatio(contentMode: contentMode)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if loading {
                ProgressView()
                    .controlSize(.small)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil, let url = URL(string: raw), !raw.isEmpty else {
            loading = false
            return
        }
        if let cached = BoomaImageCache.shared.image(for: raw) {
            image = cached
            loading = false
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let loaded = UIImage(data: data) else {
                DispatchQueue.main.async { loading = false }
                return
            }
            BoomaImageCache.shared.store(loaded, for: raw)
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.12)) { image = loaded }
                loading = false
            }
        }.resume()
    }
}

@available(iOS 15.0, *)
private struct NativeAppSheetSwiftUIView: View {
    let app: [String: Any]
    @ObservedObject var model: NativeAppSheetStateModel
    let isArabic: Bool
    let isDark: Bool
    let action: (String, Any?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreenshot: String?
    @State private var showScreenshot = false

    private var name: String { app["displayName"] as? String ?? app["name"] as? String ?? "" }
    private var subtitle: String { app["displaySubtitle"] as? String ?? "" }
    private var iconURL: URL? { URL(string: app["iconUrl"] as? String ?? "") }
    private var screenshots: [String] { app["screenshots"] as? [String] ?? [] }
    private var category: String { app["categoryDisplay"] as? String ?? app["category"] as? String ?? "" }
    private var version: String { app["version"] as? String ?? "" }
    private var developer: String { app["developerName"] as? String ?? "" }
    private var createdAt: String { app["createdAtDisplay"] as? String ?? "" }
    private var similar: [[String: Any]] { app["similarApps"] as? [[String: Any]] ?? [] }
    private var recommended: [[String: Any]] { app["recommendedApps"] as? [[String: Any]] ?? [] }
    private var hasFile: Bool { model.state["hasFile"] as? Bool ?? false }
    private var downloading: Bool { model.state["downloading"] as? Bool ?? false }
    private var paused: Bool { model.state["paused"] as? Bool ?? false }
    private var progress: Double { model.state["progress"] as? Double ?? 0 }
    private var autoSign: Bool { model.state["autoSign"] as? Bool ?? false }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appHeader

                    Divider()
                    HStack(spacing: 0) {
                        nativeStat(isArabic ? "الإصدار" : "VERSION", version.isEmpty ? "—" : version, "number")
                        Divider().frame(height: 48)
                        nativeStat(isArabic ? "التصنيف" : "CATEGORY", category.isEmpty ? "—" : category, "square.grid.2x2")
                        Divider().frame(height: 48)
                        nativeStat(isArabic ? "المطور" : "DEVELOPER", developer.isEmpty ? "—" : developer, "person.crop.square")
                    }.padding(.vertical, 8)
                    Divider()

                    if !screenshots.isEmpty {
                        sectionTitle(isArabic ? "المعاينة" : "Preview")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(screenshots, id: \.self) { raw in
                                    Button {
                                        selectedScreenshot = raw
                                        showScreenshot = true
                                    } label: {
                                        AsyncImage(url: URL(string: raw)) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                            else { ProgressView() }
                                        }
                                        .frame(width: 190, height: 360)
                                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }

                    Divider()
                    sectionTitle(isArabic ? "ما الجديد" : "What's New")
                    VStack(alignment: isArabic ? .trailing : .leading, spacing: 5) {
                        Text(version.isEmpty ? (isArabic ? "معلومات الإصدار غير متوفرة" : "Version information is unavailable") : "\(isArabic ? "الإصدار" : "Version") \(version)")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(isArabic ? .trailing : .leading)
                        if !createdAt.isEmpty { Text(createdAt).font(.caption).foregroundStyle(.tertiary) }
                    }
                    .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
                    .environment(\.layoutDirection, .leftToRight)

                    if !subtitle.isEmpty {
                        Divider()
                        sectionTitle(isArabic ? "حول التطبيق" : "About this app")
                        Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(isArabic ? .trailing : .leading).frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading).environment(\.layoutDirection, .leftToRight)
                    }

                    if !similar.isEmpty {
                        Divider()
                        sectionTitle(isArabic ? "تطبيقات مشابهة" : "Similar Apps")
                        relatedShelf(similar)
                    }

                    if !recommended.isEmpty {
                        Divider()
                        sectionTitle(isArabic ? "تطبيقات قد تعجبك" : "You Might Also Like")
                        relatedShelf(recommended)
                    }
                }
                .padding(20)
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading: Menu {
                    Toggle(isOn: Binding(
                        get: { autoSign },
                        set: { next in
                            model.update(["autoSign": next])
                            action("toggle_auto_sign", next)
                        }
                    )) {
                        Label(isArabic ? "التوقيع التلقائي بعد التنزيل" : "Auto-sign after download",
                              systemImage: "signature")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                },
                trailing: Button { dismiss() } label: {
                    Image(systemName: isArabic ? "chevron.right" : "chevron.left")
                        .font(.body.weight(.semibold))
                }.buttonStyle(.plain)
            )
            .fullScreenCover(isPresented: $showScreenshot) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let raw = selectedScreenshot {
                        AsyncImage(url: URL(string: raw)) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() }
                            else { ProgressView().tint(.white) }
                        }
                        .ignoresSafeArea(edges: .horizontal)
                    }
                    VStack {
                        HStack {
                            Spacer()
                            Button { showScreenshot = false } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .padding()
                        }
                        Spacer()
                    }
                }
            }
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(isDark ? .dark : .light)
    }

    @ViewBuilder private var appHeader: some View {
        if isArabic {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .trailing, spacing: 7) {
                    Text(name).font(.title2.bold()).lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    actionButton.frame(minWidth: 148, alignment: .trailing)
                }
                appIcon
            }
            .environment(\.layoutDirection, .leftToRight)
        } else {
            HStack(alignment: .top, spacing: 16) {
                appIcon
                VStack(alignment: .leading, spacing: 7) {
                    Text(name).font(.title2.bold()).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }
                    actionButton.frame(minWidth: 148, alignment: .leading)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var appIcon: some View {
        Group {
            if let raw = app["iconUrl"] as? String, !raw.isEmpty {
                BoomaCachedRemoteImage(raw, contentMode: .fill)
            } else {
                Image("NoIcon")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func relatedShelf(_ items: [[String: Any]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .center, spacing: 7) {
                        AsyncImage(url: URL(string: item["iconUrl"] as? String ?? "")) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Image("NoIcon").resizable().scaledToFill() }
                        }
                        .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(item["displayName"] as? String ?? "").font(.caption.bold()).lineLimit(1).frame(width: 92)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if downloading {
            Button { action("pause", nil) } label: {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.24), lineWidth: 2.6)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, progress)))
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.18), value: progress)
                    Image(systemName: paused ? "play.fill" : "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        } else if hasFile {
            Button { action("sign", nil); dismiss() } label: {
                Text(isArabic ? "توقيع" : "Sign").frame(minWidth: 148)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
        } else {
            Button {
                model.update(["downloading": true, "paused": false, "progress": 0.0])
                action("download", nil)
            } label: {
                Text(isArabic ? "تنزيل" : "GET").frame(minWidth: 148)
            }
            .modifier(NativeProminentGlassButtonModifier())
        }
    }

    private func nativeStat(_ label: String, _ value: String, _ image: String) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Image(systemName: image).font(.title3)
            Text(value).font(.caption).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
}

@available(iOS 15.0, *)
private struct NativeGlassButtonModifier: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.buttonStyle(.glass) }
        else { content.buttonStyle(.bordered) }
    }
}

@available(iOS 15.0, *)
private struct NativeProminentGlassButtonModifier: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.buttonStyle(.glassProminent) }
        else { content.buttonStyle(.borderedProminent) }
    }
}
