import Flutter
import UIKit
import SwiftUI

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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    fileprivate static func presentAppSheet(_ payload: [String: Any]) {
        guard let presenter = topViewController() else { return }
        let app = payload["app"] as? [String: Any] ?? [:]
        let state = payload["state"] as? [String: Any] ?? [:]
        let isArabic = payload["isArabic"] as? Bool ?? false
        let view = NativeAppSheetSwiftUIView(app: app, state: state, isArabic: isArabic) { action in
            appSheetChannel?.invokeMethod("action", arguments: ["id": app["id"] as? String ?? "", "action": action])
        }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
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
}

extension NativeSystemTabBarPlugin {
    static func registerNativeControls(with registrar: FlutterPluginRegistrar) {
        registrar.register(NativeSystemButtonFactory(messenger: registrar.messenger()), withId: NativeControlNames.button)
        registrar.register(NativeSystemTextFieldFactory(messenger: registrar.messenger()), withId: NativeControlNames.textField)
        registrar.register(NativeSystemCategoriesFactory(messenger: registrar.messenger()), withId: NativeControlNames.categories)
        registrar.register(NativeAppCardFactory(messenger: registrar.messenger()), withId: NativeControlNames.appCard)
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
    let scroll = UIScrollView()
    let stack = UIStackView()
    let bridge: NativeControlBridge
    let selected: String?
    var values: [String] = []

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        let p = args as? [String: Any] ?? [:]
        selected = p["selected"] as? String
        super.init()
        values = p["values"] as? [String] ?? []
        let labels = p["labels"] as? [String] ?? values
        scroll.frame = frame
        scroll.showsHorizontalScrollIndicator = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        addButton(title: NSLocalizedString("All", comment: ""), value: "", selected: self.selected == nil)
        for (i, value) in values.enumerated() {
            addButton(title: i < labels.count ? labels[i] : value, value: value, selected: value == self.selected)
        }
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
        b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        stack.addArrangedSubview(b)
    }
    @objc private func tapped(_ sender: UIButton) { bridge.channel.invokeMethod("selected", arguments: sender.accessibilityIdentifier ?? "") }
    func view() -> UIView { scroll }
}

private final class NativeAppCardFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeAppCardView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

private final class NativeAppCardView: NSObject, FlutterPlatformView {
    let root = UIControl()
    let bridge: NativeControlBridge
    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        bridge = NativeControlBridge(messenger: messenger, viewId: viewId)
        super.init()
        let p = args as? [String: Any] ?? [:]
        let app = p["app"] as? [String: Any] ?? [:]
        let state = p["state"] as? [String: Any] ?? [:]
        root.frame = frame
        root.backgroundColor = .clear
        root.addTarget(self, action: #selector(cardTapped), for: .touchUpInside)

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
        root.addSubview(icon)
        if let urlString = app["iconUrl"] as? String, let url = URL(string: urlString), !urlString.isEmpty {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { icon.image = image }
            }.resume()
        } else { icon.image = UIImage(systemName: "app.fill") }

        let name = UILabel()
        name.font = .preferredFont(forTextStyle: .headline)
        name.adjustsFontForContentSizeCategory = true
        name.text = app["displayName"] as? String ?? app["name"] as? String ?? ""
        name.numberOfLines = 1

        let subtitle = UILabel()
        subtitle.font = .preferredFont(forTextStyle: .caption1)
        subtitle.textColor = .secondaryLabel
        subtitle.text = app["displaySubtitle"] as? String ?? ""
        subtitle.numberOfLines = 1

        let meta = UILabel()
        meta.font = .preferredFont(forTextStyle: .caption2)
        meta.textColor = .tertiaryLabel
        meta.text = app["meta"] as? String ?? ""
        meta.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [name, subtitle, meta])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(labels)

        let action = UIButton(type: .system)
        action.translatesAutoresizingMaskIntoConstraints = false
        let downloading = state["downloading"] as? Bool ?? false
        let paused = state["paused"] as? Bool ?? false
        let hasFile = state["hasFile"] as? Bool ?? false
        let stage = state["stage"] as? String ?? ""
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) { config = .prominentGlass() } else { config = .filled() }
        config.cornerStyle = .capsule
        if downloading {
            config.title = paused ? "▶︎" : "Ⅱ"
            action.accessibilityIdentifier = "pause"
        } else if stage == "signing" || stage == "installing" {
            config.title = stage == "signing" ? "Signing…" : "Installing…"
            action.isEnabled = false
        } else if hasFile {
            config.title = "Sign"
            action.accessibilityIdentifier = "sign"
        } else {
            config.title = "GET"
            action.accessibilityIdentifier = "download"
        }
        action.configuration = config
        action.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        root.addSubview(action)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: root.leadingAnchor), background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            background.topAnchor.constraint(equalTo: root.topAnchor), background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), icon.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 62), icon.heightAnchor.constraint(equalToConstant: 62),
            action.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), action.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            action.widthAnchor.constraint(greaterThanOrEqualToConstant: 72), action.heightAnchor.constraint(equalToConstant: 40),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), labels.trailingAnchor.constraint(lessThanOrEqualTo: action.leadingAnchor, constant: -10), labels.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])
    }

    @objc private func cardTapped() { bridge.channel.invokeMethod("tap", arguments: nil) }
    @objc private func actionTapped(_ sender: UIButton) {
        bridge.channel.invokeMethod(sender.accessibilityIdentifier ?? "download", arguments: nil)
    }
    func view() -> UIView { root }
}

@available(iOS 15.0, *)
private struct NativeAppSheetSwiftUIView: View {
    let app: [String: Any]
    let state: [String: Any]
    let isArabic: Bool
    let action: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var name: String { app["displayName"] as? String ?? app["name"] as? String ?? "" }
    private var subtitle: String { app["displaySubtitle"] as? String ?? "" }
    private var iconURL: URL? { URL(string: app["iconUrl"] as? String ?? "") }
    private var screenshots: [String] { app["screenshots"] as? [String] ?? [] }
    private var category: String { app["categoryDisplay"] as? String ?? app["category"] as? String ?? "" }
    private var version: String { app["version"] as? String ?? "" }
    private var developer: String { app["developerName"] as? String ?? "" }
    private var hasFile: Bool { state["hasFile"] as? Bool ?? false }
    private var downloading: Bool { state["downloading"] as? Bool ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        AsyncImage(url: iconURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Image(systemName: "app.fill").font(.system(size: 42)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                        }
                        .frame(width: 104, height: 104).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        VStack(alignment: .leading, spacing: 7) {
                            Text(name).font(.title2.bold()).lineLimit(2)
                            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                            actionButton
                        }
                    }

                    HStack(spacing: 0) {
                        nativeStat(isArabic ? "الإصدار" : "VERSION", version.isEmpty ? "—" : version, "number")
                        Divider().frame(height: 42)
                        nativeStat(isArabic ? "التصنيف" : "CATEGORY", category.isEmpty ? "—" : category, "square.grid.2x2")
                        Divider().frame(height: 42)
                        nativeStat(isArabic ? "المطور" : "DEVELOPER", developer.isEmpty ? "—" : developer, "person.crop.square")
                    }
                    .padding(.vertical, 8)

                    if !screenshots.isEmpty {
                        Text(isArabic ? "المعاينة" : "Preview").font(.title3.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(screenshots, id: \.self) { raw in
                                    AsyncImage(url: URL(string: raw)) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { ProgressView() }
                                    }
                                    .frame(width: 190, height: 360).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                }
                            }
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(isArabic ? "حول التطبيق" : "About").font(.title3.bold())
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: isArabic ? "chevron.right" : "chevron.left") }
                        .modifier(NativeGlassButtonModifier())
                }
            }
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        }
    }

    @ViewBuilder private var actionButton: some View {
        if downloading {
            Button { action("pause") } label: { Label(isArabic ? "إيقاف مؤقت" : "Pause", systemImage: "pause.fill") }
                .modifier(NativeProminentGlassButtonModifier())
        } else if hasFile {
            Button { action("sign"); dismiss() } label: { Text(isArabic ? "توقيع" : "Sign") }
                .modifier(NativeProminentGlassButtonModifier())
        } else {
            Button { action("download") } label: { Text(isArabic ? "تنزيل" : "GET") }
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
