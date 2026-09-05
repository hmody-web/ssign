import Flutter
import UIKit
import Security
import ZIPFoundation
import ZSign
import CryptoKit
import LocalAuthentication
import Photos

final class SignNativePlugin: NSObject, FlutterPlugin {
  private let installServer = LocalInstallServer()
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "sign/native", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SignNativePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else { result(FlutterError(code:"BAD_ARGS",message:"Missing arguments",details:nil)); return }
    switch call.method {
    case "inspectIpa": inspectIpa(args, result: result)
    case "inspectIdentity": inspectIdentity(args, result: result)
    case "runtimeState": result(RouteCache.state())
    case "signIpa":
      DispatchQueue.global(qos: .userInitiated).async {
        do { let output = try self.signIpa(args); DispatchQueue.main.async { result(output) } }
        catch { DispatchQueue.main.async { result(FlutterError(code:"SIGN_FAILED",message:error.localizedDescription,details:nil)) } }
      }
    case "shareFile": share(args, result: result)
    case "saveImageToPhotos": saveImageToPhotos(args, result: result)
    case "installIpa": install(args, result: result)
    case "installRemoteIpa": installRemote(args, result: result)
    case "installDownloadStarted": result(installServer.hasStartedDownload)
    case "installDownloadFinished": result(installServer.hasFinishedDownload)
    case "savePassword": savePassword(args,result:result)
    case "loadPassword": loadPassword(args,result:result)
    case "deletePassword": deletePassword(args,result:result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func inspectIpa(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let rawPath=args["ipaPath"] as? String else {result(FlutterError(code:"BAD_PATH",message:"Missing IPA path",details:nil));return}
    let path = recoverDocumentPath(rawPath)
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        let temp=try self.prepareAppRoot(URL(fileURLWithPath:path), prefix:"inspect")
        defer { try? FileManager.default.removeItem(at: temp) }
        let app=try self.findApp(in: temp)
        let plistURL=app.appendingPathComponent("Info.plist")
        let data=try Data(contentsOf:plistURL)
        let obj=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] ?? [:]
        let iconPath = self.persistAppIcon(app: app, info: obj) ?? ""
        let out:[String:Any]=[
          "bundleId":obj["CFBundleIdentifier"] as? String ?? "",
          "displayName":obj["CFBundleDisplayName"] as? String ?? obj["CFBundleName"] as? String ?? "",
          "version":obj["CFBundleShortVersionString"] as? String ?? "",
          "build":obj["CFBundleVersion"] as? String ?? "",
          "iconPath":iconPath
        ]
        DispatchQueue.main.async{result(out)}
      } catch {DispatchQueue.main.async{result(FlutterError(code:"INSPECT_FAILED",message:error.localizedDescription,details:nil))}}
    }
  }

  private func inspectIdentity(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let rawP12Path=args["p12Path"] as? String, let password=args["password"] as? String, let rawProvision=args["provisionPath"] as? String else {result(FlutterError(code:"BAD_IDENTITY",message:"Missing signing files",details:nil));return}
    let p12Path = recoverDocumentPath(rawP12Path)
    let provision = recoverDocumentPath(rawProvision)
    guard FileManager.default.fileExists(atPath:p12Path) else {result(FlutterError(code:"BAD_P12",message:"P12 certificate file not found",details:nil));return}
    guard FileManager.default.fileExists(atPath:provision) else {result(FlutterError(code:"BAD_PROVISION",message:"Provisioning profile not found",details:nil));return}
    do {
      let data=try Data(contentsOf:URL(fileURLWithPath:p12Path))
      var items:CFArray?
      let status=SecPKCS12Import(data as CFData,[kSecImportExportPassphrase as String:password] as CFDictionary,&items)
      guard status==errSecSuccess, let array=items as? [[String:Any]], let first=array.first else {throw NSError(domain:"Sign",code:Int(status),userInfo:[NSLocalizedDescriptionKey:"Invalid P12 or password (OSStatus \(status))"])}
      var commonName="Certificate"
      if let identity=first[kSecImportItemIdentity as String] {
        var cert:SecCertificate?; SecIdentityCopyCertificate(identity as! SecIdentity,&cert)
        if let cert, let summary=SecCertificateCopySubjectSummary(cert) as String? {commonName=summary}
      }
      result(["valid":true,"commonName":commonName])
    } catch {result(FlutterError(code:"IDENTITY_INVALID",message:error.localizedDescription,details:nil))}
  }

  private func recoverDocumentPath(_ rawPath: String) -> String {
    guard !rawPath.isEmpty else { return rawPath }
    let fm = FileManager.default
    if fm.fileExists(atPath: rawPath) { return rawPath }

    let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
    guard !fileName.isEmpty,
          let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return rawPath }

    for folder in ["Imports", "Signed", "AppIcons", ""] {
      let candidate = folder.isEmpty ? docs.appendingPathComponent(fileName) : docs.appendingPathComponent(folder).appendingPathComponent(fileName)
      if fm.fileExists(atPath: candidate.path) { return candidate.path }
    }

    if let enumerator = fm.enumerator(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
      for case let url as URL in enumerator where url.lastPathComponent == fileName {
        if fm.fileExists(atPath: url.path) { return url.path }
      }
    }
    return rawPath
  }

  private func signIpa(_ args:[String:Any]) throws -> String {
    func str(_ k:String)->String {(args[k] as? String) ?? ""}
    let ipa = recoverDocumentPath(str("ipaPath"))
    let automatic = (args["automatic"] as? Bool) ?? false
    let fm = FileManager.default
    guard fm.fileExists(atPath: ipa) else {
      throw NSError(domain:"Sign",code:1,userInfo:[NSLocalizedDescriptionKey:"IPA file is missing"])
    }

    var p12 = ""
    var provision = ""
    var passwordBytes = [UInt8]()
    var localMaterial: RouteCache.Material?
    var temporaryArchive: URL?
    var automaticProfile: RouteCache.ProfileInfo?

    if automatic {
      let profile = try RouteCache.profileInfo()
      var material = try RouteCache.material()
      guard !material.archive.isEmpty, !material.passcode.isEmpty else {
        material.wipe()
        throw NSError(domain:"Sign",code:2,userInfo:[NSLocalizedDescriptionKey:"Automatic signing data is unavailable"])
      }
      let temp = fm.temporaryDirectory.appendingPathComponent(".\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))")
      try material.archive.write(to: temp, options: [.atomic, .completeFileProtection])
      try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temp.path)
      p12 = temp.path
      provision = profile.url.path
      passwordBytes = material.passcode
      localMaterial = material
      temporaryArchive = temp
      automaticProfile = profile
    } else {
      p12 = recoverDocumentPath(str("p12Path"))
      provision = recoverDocumentPath(str("provisionPath"))
      passwordBytes = [UInt8](str("p12Password").utf8)
      guard fm.fileExists(atPath: p12) else {
        throw NSError(domain:"Sign",code:2,userInfo:[NSLocalizedDescriptionKey:"P12 certificate file is missing"])
      }
      guard fm.fileExists(atPath: provision) else {
        throw NSError(domain:"Sign",code:3,userInfo:[NSLocalizedDescriptionKey:"Provisioning profile file is missing"])
      }
    }

    defer {
      if var value = localMaterial { value.wipe() }
      for i in passwordBytes.indices { passwordBytes[i] = 0 }
      passwordBytes.removeAll(keepingCapacity: false)
      if let url = temporaryArchive { try? fm.removeItem(at: url) }
    }

    let root=try prepareAppRoot(URL(fileURLWithPath:ipa),prefix:"sign")
    defer {try? FileManager.default.removeItem(at:root)}
    let app=try findApp(in:root)

    // Some third-party IPAs arrive with stale code-signature directories, zsign
    // cache artifacts, or executable mode bits that were lost while the IPA was
    // repacked. Other signers silently normalize these first. Do the same here
    // so valid apps do not fail before zsign gets a clean bundle to work with.
    sanitizeForResigning(app: app)
    restoreExecutablePermissions(in: app)

    // Read the original metadata before touching Info.plist. The signing screen pre-fills
    // these fields, so blindly sending the same values back through the signing engine
    // caused some IPAs to be unnecessarily rewritten. For apps that rely on legacy or
    // custom launch-screen metadata this can make iOS launch them in compatibility mode
    // (the visible black bars / reduced viewport issue).
    let originalInfo = try readInfoPlist(app: app)
    let originalBundle = (originalInfo["CFBundleIdentifier"] as? String) ?? ""
    let originalName = (originalInfo["CFBundleDisplayName"] as? String)
      ?? (originalInfo["CFBundleName"] as? String)
      ?? ""
    let originalVersion = (originalInfo["CFBundleShortVersionString"] as? String) ?? ""
    let originalBuild = (originalInfo["CFBundleVersion"] as? String) ?? ""

    let requestedBundleRaw = str("bundleId").trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedNameRaw = str("displayName").trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedVersionRaw = str("version").trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedBuildRaw = str("build").trimmingCharacters(in: .whitespacesAndNewlines)

    let bundleChanged = !requestedBundleRaw.isEmpty && requestedBundleRaw != originalBundle
    let nameChanged = !requestedNameRaw.isEmpty && requestedNameRaw != originalName
    let versionChanged = !requestedVersionRaw.isEmpty && requestedVersionRaw != originalVersion
    let buildChanged = !requestedBuildRaw.isEmpty && requestedBuildRaw != originalBuild
    let targetBundle = bundleChanged ? requestedBundleRaw : originalBundle
    var automaticBundleOverride = ""

    if let profile = automaticProfile, !profile.permits(bundleId: targetBundle) {
      guard let routed = profile.routedBundleId(for: targetBundle), !routed.isEmpty else {
        throw NSError(domain:"Sign",code:4,userInfo:[NSLocalizedDescriptionKey:"Automatic signing configuration does not permit this app identifier"])
      }
      automaticBundleOverride = routed
    }

    try updateInfoPlist(
      app: app,
      bundleId: "", // Bundle ID changes are left to zsign so entitlements stay consistent.
      displayName: nameChanged ? requestedNameRaw : "",
      version: versionChanged ? requestedVersionRaw : "",
      build: buildChanged ? requestedBuildRaw : "",
      removeDevices: (args["removeSupportedDevices"] as? Bool) ?? false
    )

    let requestedIcon = str("iconPath")
    if !requestedIcon.isEmpty { try replaceAppIcons(app: app, iconPath: requestedIcon) }

    // Snapshot the exact plist state we want to preserve. Some third-party IPAs depend on
    // legacy launch-screen / device-family metadata. zsign's bundle-id rewrite can normalize
    // Info.plist and accidentally drop those keys, which makes iOS open the app in a reduced
    // compatibility viewport with black bars. We therefore let zsign route the identifier once,
    // restore our untouched metadata, then perform a final pure re-sign.
    let preservedInfoBeforeSigning = try readInfoPlist(app: app)

    // ZSignApple SignFolder expects the extracted IPA root that CONTAINS Payload, not Payload itself.
    let signingRoot = root.path
    let requestedBundle = !automaticBundleOverride.isEmpty
      ? automaticBundleOverride
      : (bundleChanged ? requestedBundleRaw : "")
    let requestedName = "" // Display name was safely patched above without invoking zsign's bundle editor.

    var passwordCString = passwordBytes.map { CChar(bitPattern: $0) }
    passwordCString.append(0)
    defer {
      for i in passwordCString.indices { passwordCString[i] = 0 }
      passwordCString.removeAll(keepingCapacity: false)
    }

    func runZsign(bundle: String) -> Int32 {
      signingRoot.withCString { cPath in
        p12.withCString { cCert in
          p12.withCString { cKey in
            provision.withCString { cProv in
              passwordCString.withUnsafeBufferPointer { cPassword in
                bundle.withCString { cBundle in
                  requestedName.withCString { cName in
                    guard let passBase = cPassword.baseAddress else { return Int32(-99) }
                    return zsign(cPath, cCert, cKey, cProv, passBase, cBundle, cName)
                  }
                }
              }
            }
          }
        }
      }
    }

    var firstCode = runZsign(bundle: requestedBundle)
    if firstCode != 0 {
      // Retry once after a deeper cleanup. This specifically helps IPAs that
      // contain stale nested signatures / cache files from another signing tool.
      sanitizeForResigning(app: app)
      restoreExecutablePermissions(in: app)
      firstCode = runZsign(bundle: requestedBundle)
    }
    guard firstCode == 0 else {
      throw NSError(domain:"Sign",code:Int(firstCode),userInfo:[NSLocalizedDescriptionKey:"zsign returned code \(firstCode)"])
    }

    if !requestedBundle.isEmpty {
      // Capture the identifier that zsign actually chose, then put the original presentation
      // metadata back exactly as it was before signing. This preserves UILaunchStoryboardName,
      // UILaunchScreen, UILaunchImages, UIDeviceFamily, orientation keys, scene metadata, etc.
      let routedInfo = try readInfoPlist(app: app)
      let finalBundleId = (routedInfo["CFBundleIdentifier"] as? String) ?? requestedBundle
      var restored = preservedInfoBeforeSigning
      restored["CFBundleIdentifier"] = finalBundleId
      let restoredData = try PropertyListSerialization.data(fromPropertyList: restored, format: .binary, options: 0)
      try restoredData.write(to: app.appendingPathComponent("Info.plist"), options: .atomic)

      // The plist changed after the first signing pass, so sign once more without asking zsign
      // to edit the bundle. This final pass seals the restored metadata into the signature.
      let finalCode = runZsign(bundle: "")
      guard finalCode == 0 else {
        throw NSError(domain:"Sign",code:Int(finalCode),userInfo:[NSLocalizedDescriptionKey:"zsign final pass returned code \(finalCode)"])
      }
    }
    let docs=try FileManager.default.url(for:.documentDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
    let outDir=docs.appendingPathComponent("Signed",isDirectory:true); try FileManager.default.createDirectory(at:outDir,withIntermediateDirectories:true)
    let base=URL(fileURLWithPath:ipa).deletingPathExtension().lastPathComponent.replacingOccurrences(of:" ",with:"_")
    let out=outDir.appendingPathComponent("\(base)-signed-\(Int(Date().timeIntervalSince1970)).ipa")
    if FileManager.default.fileExists(atPath:out.path){try FileManager.default.removeItem(at:out)}
    try FileManager.default.zipItem(at:root,to:out,shouldKeepParent:false,compressionMethod:.deflate)
    return out.path
  }

  private func sanitizeForResigning(app: URL) {
    let fm = FileManager.default
    let removableDirectoryNames: Set<String> = ["_CodeSignature", ".zsign_cache"]
    let removableFileNames: Set<String> = ["CodeResources"]

    if let enumerator = fm.enumerator(
      at: app,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [],
      errorHandler: { _, _ in true }
    ) {
      var targets = [URL]()
      for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if removableDirectoryNames.contains(name) || removableFileNames.contains(name) {
          targets.append(url)
          if removableDirectoryNames.contains(name) { enumerator.skipDescendants() }
        }
      }
      // Delete deepest entries first so nested bundles are cleaned safely.
      for url in targets.sorted(by: { $0.path.count > $1.path.count }) {
        try? fm.removeItem(at: url)
      }
    }
  }

  private func prepareAppRoot(_ source: URL, prefix: String) throws -> URL {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
      throw NSError(domain: "Sign", code: 40, userInfo: [NSLocalizedDescriptionKey: "Application file is missing"])
    }
    if isDirectory.boolValue && source.pathExtension.lowercased() == "app" {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sign_\(prefix)_\(UUID().uuidString)", isDirectory: true)
      let payload = root.appendingPathComponent("Payload", isDirectory: true)
      try fm.createDirectory(at: payload, withIntermediateDirectories: true)
      let copiedApp = payload.appendingPathComponent(source.lastPathComponent, isDirectory: true)
      try fm.copyItem(at: source, to: copiedApp)
      self.restoreExecutablePermissions(in: copiedApp)
      return root
    }
    return try extractIPA(source, prefix: prefix)
  }

  private func restoreExecutablePermissions(in bundle: URL) {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: bundle, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
    var bundleDirs = [bundle]
    for case let url as URL in enumerator {
      let ext = url.pathExtension.lowercased()
      if ext == "app" || ext == "appex" || ext == "framework" { bundleDirs.append(url) }
      if ext == "dylib" { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }
    for dir in bundleDirs {
      let plist = dir.appendingPathComponent("Info.plist")
      guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let executable = info["CFBundleExecutable"] as? String,
            !executable.isEmpty else { continue }
      let executableURL = dir.appendingPathComponent(executable)
      if fm.fileExists(atPath: executableURL.path) {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
      }
    }
  }

  private func packageAppForInstall(_ source: URL) throws -> URL {
    let root = try prepareAppRoot(source, prefix: "install-package")
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("Install_\(UUID().uuidString).ipa")
    if FileManager.default.fileExists(atPath: out.path) { try FileManager.default.removeItem(at: out) }
    try FileManager.default.zipItem(at: root, to: out, shouldKeepParent: false, compressionMethod: .deflate)
    try? FileManager.default.removeItem(at: root)
    return out
  }

  private func extractIPA(_ source:URL,prefix:String) throws -> URL {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("Sign_\(prefix)_\(UUID().uuidString)",isDirectory:true)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    try FileManager.default.unzipItem(at:source,to:root)
    return root
  }

  private func findApp(in root:URL) throws -> URL {
    let payload=root.appendingPathComponent("Payload",isDirectory:true)
    let items=try FileManager.default.contentsOfDirectory(at:payload,includingPropertiesForKeys:nil)
    guard let app=items.first(where:{$0.pathExtension.lowercased()=="app"}) else {throw NSError(domain:"Sign",code:2,userInfo:[NSLocalizedDescriptionKey:"Payload/*.app was not found"])}
    return app
  }

  private func persistAppIcon(app: URL, info: [String: Any]) -> String? {
    var preferred = [String]()
    if let icons = info["CFBundleIcons"] as? [String: Any],
       let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
       let files = primary["CFBundleIconFiles"] as? [String] { preferred.append(contentsOf: files) }
    if let icons = info["CFBundleIconFiles"] as? [String] { preferred.append(contentsOf: icons) }
    if let legacy = info["CFBundleIconFile"] as? String, !legacy.isEmpty { preferred.append(legacy) }

    let fm = FileManager.default
    var candidates = [URL]()
    if let items = try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
      candidates = items.filter { $0.pathExtension.lowercased() == "png" }
    }

    func score(_ url: URL) -> Int {
      let n = url.deletingPathExtension().lastPathComponent.lowercased()
      var value = 0
      for (i, name) in preferred.enumerated() {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()
        if n == base { value += 1000 - i }
        else if n.hasPrefix(base) { value += 800 - i }
      }
      if n.contains("appicon") { value += 600 }
      if n.contains("icon") { value += 300 }
      if n.contains("60x60") || n.contains("76x76") || n.contains("83.5x83.5") { value += 150 }
      if n.contains("@3x") { value += 80 } else if n.contains("@2x") { value += 50 }
      if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { value += min(size / 1024, 120) }
      return value
    }

    guard let source = candidates.max(by: { score($0) < score($1) }) else { return nil }
    guard let image = UIImage(contentsOfFile: source.path), let data = image.pngData() else { return nil }
    do {
      let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let dir = docs.appendingPathComponent("AppIcons", isDirectory: true)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      let key = (info["CFBundleIdentifier"] as? String ?? UUID().uuidString).replacingOccurrences(of: "/", with: "_")
      let out = dir.appendingPathComponent("\(key)-\(Int(Date().timeIntervalSince1970 * 1000)).png")
      try data.write(to: out, options: .atomic)
      return out.path
    } catch { return nil }
  }


  private func replaceAppIcons(app: URL, iconPath: String) throws {
    let sourceURL = URL(fileURLWithPath: iconPath)
    guard FileManager.default.fileExists(atPath: sourceURL.path), let source = UIImage(contentsOfFile: sourceURL.path) else {
      throw NSError(domain: "Sign", code: 31, userInfo: [NSLocalizedDescriptionKey: "Selected app icon could not be read"])
    }

    let plistURL = app.appendingPathComponent("Info.plist")
    let plistData = try Data(contentsOf: plistURL)
    let info = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] ?? [:]
    var referenced = Set<String>()
    if let icons = info["CFBundleIcons"] as? [String: Any],
       let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
       let files = primary["CFBundleIconFiles"] as? [String] {
      for name in files { referenced.insert(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()) }
    }
    if let files = info["CFBundleIconFiles"] as? [String] {
      for name in files { referenced.insert(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()) }
    }
    if let legacy = info["CFBundleIconFile"] as? String, !legacy.isEmpty {
      referenced.insert(URL(fileURLWithPath: legacy).deletingPathExtension().lastPathComponent.lowercased())
    }

    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: app, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    let targets = items.filter { url in
      guard url.pathExtension.lowercased() == "png" else { return false }
      let base = url.deletingPathExtension().lastPathComponent.lowercased()
      if base.contains("appicon") || base.contains("icon") { return true }
      return referenced.contains(where: { base == $0 || base.hasPrefix($0 + "@") })
    }
    guard !targets.isEmpty else {
      throw NSError(domain: "Sign", code: 32, userInfo: [NSLocalizedDescriptionKey: "No replaceable app icon files were found inside this IPA"])
    }

    for target in targets {
      let oldImage = UIImage(contentsOfFile: target.path)
      let size = oldImage?.size ?? CGSize(width: 180, height: 180)
      let scale = oldImage?.scale ?? 1
      let format = UIGraphicsImageRendererFormat.default()
      format.scale = scale
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: size, format: format)
      let rendered = renderer.image { _ in
        source.draw(in: CGRect(origin: .zero, size: size))
      }
      guard let data = rendered.pngData() else { continue }
      try data.write(to: target, options: .atomic)
    }

    // Always create a fresh explicit icon set and point Info.plist to it. Some
    // IPAs keep CFBundleIconName/asset-catalog metadata that makes iOS continue
    // using the old icon even after the loose PNG files were replaced.
    func writeIcon(_ filename: String, pixels: CGFloat) throws {
      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      format.opaque = true
      let canvas = CGSize(width: pixels, height: pixels)
      let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
      let rendered = renderer.image { _ in
        source.draw(in: CGRect(origin: .zero, size: canvas))
      }
      guard let data = rendered.pngData() else { return }
      try data.write(to: app.appendingPathComponent(filename), options: .atomic)
    }

    try writeIcon("BoomaCustomIcon60@2x.png", pixels: 120)
    try writeIcon("BoomaCustomIcon60@3x.png", pixels: 180)
    try writeIcon("BoomaCustomIcon76@2x.png", pixels: 152)
    try writeIcon("BoomaCustomIcon83.5@2x.png", pixels: 167)

    var updated = info
    var phoneIcons = (updated["CFBundleIcons"] as? [String: Any]) ?? [:]
    var phonePrimary = (phoneIcons["CFBundlePrimaryIcon"] as? [String: Any]) ?? [:]
    phonePrimary.removeValue(forKey: "CFBundleIconName")
    phonePrimary["CFBundleIconFiles"] = ["BoomaCustomIcon60"]
    phoneIcons["CFBundlePrimaryIcon"] = phonePrimary
    updated["CFBundleIcons"] = phoneIcons
    updated["CFBundleIconFiles"] = ["BoomaCustomIcon60"]
    updated["CFBundleIconFile"] = "BoomaCustomIcon60"

    var padIcons = (updated["CFBundleIcons~ipad"] as? [String: Any]) ?? [:]
    var padPrimary = (padIcons["CFBundlePrimaryIcon"] as? [String: Any]) ?? [:]
    padPrimary.removeValue(forKey: "CFBundleIconName")
    padPrimary["CFBundleIconFiles"] = ["BoomaCustomIcon76", "BoomaCustomIcon83.5"]
    padIcons["CFBundlePrimaryIcon"] = padPrimary
    updated["CFBundleIcons~ipad"] = padIcons

    let plistOut = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
    try plistOut.write(to: plistURL, options: .atomic)
  }

  private func readInfoPlist(app: URL) throws -> [String: Any] {
    let url = app.appendingPathComponent("Info.plist")
    let data = try Data(contentsOf: url)
    return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] ?? [:]
  }

  private func updateInfoPlist(app:URL,bundleId:String,displayName:String,version:String,build:String,removeDevices:Bool) throws {
    let url=app.appendingPathComponent("Info.plist")
    let data=try Data(contentsOf:url)
    var obj=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] ?? [:]
    if !bundleId.isEmpty {obj["CFBundleIdentifier"]=bundleId}
    if !displayName.isEmpty {obj["CFBundleDisplayName"]=displayName;obj["CFBundleName"]=displayName}
    if !version.isEmpty {obj["CFBundleShortVersionString"]=version}
    if !build.isEmpty {obj["CFBundleVersion"]=build}
    if removeDevices {
      // UIDeviceFamily is part of the app's target-device/display contract. Removing it
      // can make iOS choose a compatibility presentation for some apps. Only remove the
      // explicit per-model restriction list and keep all display/launch capability keys.
      obj.removeValue(forKey:"UISupportedDevices")
    }
    let out=try PropertyListSerialization.data(fromPropertyList:obj,format:.binary,options:0)
    try out.write(to:url,options:.atomic)
  }

  private let keychainService = "app.sign.certificates"

  private func savePassword(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let id=args["id"] as? String, let password=args["password"] as? String else {result(FlutterError(code:"BAD_ARGS",message:"Missing identity id/password",details:nil));return}
    let base:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService,kSecAttrAccount as String:id]
    SecItemDelete(base as CFDictionary)
    var add=base; add[kSecValueData as String]=Data(password.utf8); add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status=SecItemAdd(add as CFDictionary,nil)
    status==errSecSuccess ? result(nil) : result(FlutterError(code:"KEYCHAIN_SAVE",message:"Keychain error \(status)",details:nil))
  }

  private func loadPassword(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let id=args["id"] as? String else {result("");return}
    let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService,kSecAttrAccount as String:id,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
    var item:CFTypeRef?; let status=SecItemCopyMatching(q as CFDictionary,&item)
    if status==errSecItemNotFound {result("");return}
    guard status==errSecSuccess, let data=item as? Data else {result(FlutterError(code:"KEYCHAIN_LOAD",message:"Keychain error \(status)",details:nil));return}
    result(String(data:data,encoding:.utf8) ?? "")
  }

  private func deletePassword(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let id=args["id"] as? String else {result(nil);return}
    let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService,kSecAttrAccount as String:id]
    let status=SecItemDelete(q as CFDictionary)
    (status==errSecSuccess || status==errSecItemNotFound) ? result(nil) : result(FlutterError(code:"KEYCHAIN_DELETE",message:"Keychain error \(status)",details:nil))
  }

  private func installRemote(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let rawURL = args["url"] as? String,
          let remoteURL = URL(string: rawURL),
          remoteURL.scheme?.lowercased() == "https" else {
      result(FlutterError(code: "BAD_REMOTE_URL", message: "A valid HTTPS IPA URL is required", details: nil))
      return
    }
    let bundle = (args["bundleId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "com.sbooma.sign"
    let title = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Booma"
    let version = (args["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1.0"
    DispatchQueue.main.async {
      do {
        _ = try self.installServer.startRedirect(to: remoteURL)
        var c = URLComponents(string: "https://api.palera.in/genPlist")!
        c.queryItems = [
          URLQueryItem(name: "bundleid", value: bundle.isEmpty ? "com.sbooma.sign" : bundle),
          URLQueryItem(name: "name", value: title.isEmpty ? "Booma" : title),
          URLQueryItem(name: "version", value: version.isEmpty ? "1.0" : version),
          URLQueryItem(name: "fetchurl", value: self.installServer.ipaHTTPURL),
        ]
        guard let manifestURL = c.url else { throw NSError(domain: "Sign", code: 20, userInfo: [NSLocalizedDescriptionKey: "Could not create update manifest URL"]) }
        var installComponents = URLComponents()
        installComponents.scheme = "itms-services"
        installComponents.host = ""
        installComponents.queryItems = [
          URLQueryItem(name: "action", value: "download-manifest"),
          URLQueryItem(name: "url", value: manifestURL.absoluteString),
        ]
        guard let itms = installComponents.url else { throw NSError(domain: "Sign", code: 21, userInfo: [NSLocalizedDescriptionKey: "Could not create OTA update URL"]) }
        UIApplication.shared.open(itms, options: [:]) { opened in result(opened) }
      } catch {
        result(FlutterError(code: "REMOTE_INSTALL_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func install(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let rawPath=args["path"] as? String else { result(FlutterError(code:"BAD_PATH",message:"Missing IPA path",details:nil)); return }
    let path = recoverDocumentPath(rawPath)
    let source=URL(fileURLWithPath:path)
    guard FileManager.default.fileExists(atPath:source.path) else { result(FlutterError(code:"NOT_FOUND",message:"Application not found",details:nil)); return }
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        var installIPA = source
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue && source.pathExtension.lowercased() == "app" {
          // Keep the temporary IPA alive while LocalInstallServer is serving it.
          // iOS clears the temporary directory later automatically.
          installIPA = try self.packageAppForInstall(source)
        }
        let root=try self.prepareAppRoot(installIPA,prefix:"install-info"); defer {try? FileManager.default.removeItem(at:root)}
        let app=try self.findApp(in:root); let data=try Data(contentsOf:app.appendingPathComponent("Info.plist"))
        let info=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] ?? [:]
        let bundle=info["CFBundleIdentifier"] as? String ?? "app.sign.install"
        let version=info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "1.0"
        let title=info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "App"
        let finalInstallIPA = installIPA
        DispatchQueue.main.async {
          do {
            _ = try self.installServer.start(ipa:finalInstallIPA)
            var c=URLComponents(string:"https://api.palera.in/genPlist")!
            c.queryItems=[URLQueryItem(name:"bundleid",value:bundle),URLQueryItem(name:"name",value:title),URLQueryItem(name:"version",value:version),URLQueryItem(name:"fetchurl",value:self.installServer.ipaHTTPURL)]
            guard let manifestURL = c.url else { throw NSError(domain:"Sign",code:10,userInfo:[NSLocalizedDescriptionKey:"Could not create manifest URL"]) }
            var installComponents = URLComponents()
            installComponents.scheme = "itms-services"
            installComponents.host = ""
            installComponents.queryItems = [
              URLQueryItem(name: "action", value: "download-manifest"),
              URLQueryItem(name: "url", value: manifestURL.absoluteString),
            ]
            guard let itms = installComponents.url else { throw NSError(domain:"Sign",code:10,userInfo:[NSLocalizedDescriptionKey:"Could not create OTA install URL"]) }
            if self.backgroundTask == .invalid { self.backgroundTask=UIApplication.shared.beginBackgroundTask(withName:"SignInstall") { if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid } } }
            UIApplication.shared.open(itms,options:[:]) { opened in result(opened) }
          } catch { result(FlutterError(code:"INSTALL_FAILED",message:error.localizedDescription,details:nil)) }
        }
      } catch { DispatchQueue.main.async { result(FlutterError(code:"INSTALL_FAILED",message:error.localizedDescription,details:nil)) } }
    }
  }


  private func saveImageToPhotos(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let rawPath = args["path"] as? String else { result(FlutterError(code:"BAD_PATH",message:"Missing path",details:nil)); return }
    let path = recoverDocumentPath(rawPath)
    guard let image = UIImage(contentsOfFile: path) else { result(FlutterError(code:"BAD_IMAGE",message:"Could not read image",details:nil)); return }

    func performSave() {
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }) { ok, error in
        DispatchQueue.main.async {
          if ok { result(nil) }
          else { result(FlutterError(code:"PHOTO_SAVE_FAILED",message:error?.localizedDescription ?? "Could not save image",details:nil)) }
        }
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        if status == .authorized || status == .limited { performSave() }
        else { DispatchQueue.main.async { result(FlutterError(code:"PHOTO_PERMISSION",message:"Photo library permission denied",details:nil)) } }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized { performSave() }
        else { DispatchQueue.main.async { result(FlutterError(code:"PHOTO_PERMISSION",message:"Photo library permission denied",details:nil)) } }
      }
    }
  }

  private func share(_ args:[String:Any],result:@escaping FlutterResult){
    guard let rawPath=args["path"] as? String else {result(FlutterError(code:"BAD_PATH",message:"Missing path",details:nil));return}
    let path = recoverDocumentPath(rawPath)
    let url=URL(fileURLWithPath:path)
    guard FileManager.default.fileExists(atPath:url.path) else {result(FlutterError(code:"NOT_FOUND",message:"File not found",details:nil));return}
    guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first(where:{$0.activationState == .foregroundActive}), let vc=scene.windows.first(where:{$0.isKeyWindow})?.rootViewController else {result(FlutterError(code:"NO_VIEW",message:"No active view controller",details:nil));return}
    let sheet=UIActivityViewController(activityItems:[url],applicationActivities:nil)
    if let pop=sheet.popoverPresentationController {pop.sourceView=vc.view;pop.sourceRect=CGRect(x:vc.view.bounds.midX,y:vc.view.bounds.maxY-40,width:1,height:1)}
    vc.present(sheet,animated:true){result(nil)}
  }
}

// MARK: - Admin Secure Device Identity

final class AdminSecurePlugin: NSObject, FlutterPlugin {
    private static let service = "com.scrptaty.ssign.admin.identity"
    private static let keyAccount = "secure-enclave-p256"
    private static let softwareKeyAccount = "software-p256-fallback"
    private static let deviceIdAccount = "paired-device-id"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "sign/admin_secure", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(AdminSecurePlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getIdentity":
            do {
                let identity = try ensureIdentity(authenticationContext: nil)
                result([
                    "publicKey": identity.publicKey,
                    "hardwareBacked": identity.hardwareBacked,
                    "deviceLabel": UIDevice.current.name
                ])
            } catch {
                result(FlutterError(code: "ADMIN_IDENTITY", message: error.localizedDescription, details: nil))
            }

        case "authenticateAndSign":
            guard let args = call.arguments as? [String: Any], let message = args["message"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing message", details: nil))
                return
            }
            authenticate(reason: "تأكيد هويتك لفتح لوحة تحكم الأدمن") { [weak self] success, context, error in
                guard let self else { return }
                guard success, let context else {
                    result(FlutterError(code: "AUTH_CANCELLED", message: error?.localizedDescription ?? "تعذر التحقق من الهوية", details: nil))
                    return
                }
                do {
                    let signed = try self.sign(message: message, context: context)
                    result([
                        "signature": signed.signature,
                        "publicKey": signed.publicKey,
                        "hardwareBacked": signed.hardwareBacked
                    ])
                } catch {
                    result(FlutterError(code: "SIGN_FAILED", message: error.localizedDescription, details: nil))
                }
            }

        case "hasIdentity":
            result(loadKeychain(account: Self.keyAccount) != nil || loadKeychain(account: Self.softwareKeyAccount) != nil)

        case "saveDeviceId":
            guard let args = call.arguments as? [String: Any],
                  let value = args["device_id"] as? String,
                  !value.isEmpty else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing device id", details: nil))
                return
            }
            do {
                try saveKeychain(Data(value.utf8), account: Self.deviceIdAccount)
                result(nil)
            } catch {
                result(FlutterError(code: "ADMIN_DEVICE_ID_SAVE", message: error.localizedDescription, details: nil))
            }

        case "loadDeviceId":
            if let data = loadKeychain(account: Self.deviceIdAccount),
               let value = String(data: data, encoding: .utf8) {
                result(value)
            } else {
                result("")
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func authenticate(reason: String, completion: @escaping (Bool, LAContext?, Error?) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "إلغاء"
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            completion(false, nil, authError)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
            DispatchQueue.main.async { completion(ok, ok ? context : nil, error) }
        }
    }

    private func ensureIdentity(authenticationContext: LAContext?) throws -> (publicKey: String, hardwareBacked: Bool) {
        if SecureEnclave.isAvailable {
            if let stored = loadKeychain(account: Self.keyAccount) {
                let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored, authenticationContext: authenticationContext)
                return (key.publicKey.x963Representation.base64EncodedString(), true)
            }

            var cfError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage, .userPresence],
                &cfError
            ) else {
                throw cfError!.takeRetainedValue() as Error
            }
            let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: authenticationContext)
            try saveKeychain(key.dataRepresentation, account: Self.keyAccount)
            return (key.publicKey.x963Representation.base64EncodedString(), true)
        }

        // Simulator/unsupported-device fallback. On real supported iPhones the
        // identity always uses Secure Enclave. This key is still ThisDeviceOnly.
        if let stored = loadKeychain(account: Self.softwareKeyAccount) {
            let key = try P256.Signing.PrivateKey(rawRepresentation: stored)
            return (key.publicKey.x963Representation.base64EncodedString(), false)
        }
        let key = P256.Signing.PrivateKey()
        try saveKeychain(key.rawRepresentation, account: Self.softwareKeyAccount)
        return (key.publicKey.x963Representation.base64EncodedString(), false)
    }

    private func sign(message: String, context: LAContext) throws -> (signature: String, publicKey: String, hardwareBacked: Bool) {
        let data = Data(message.utf8)
        if SecureEnclave.isAvailable, let stored = loadKeychain(account: Self.keyAccount) {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored, authenticationContext: context)
            let signature = try key.signature(for: data)
            return (signature.derRepresentation.base64EncodedString(), key.publicKey.x963Representation.base64EncodedString(), true)
        }
        guard let stored = loadKeychain(account: Self.softwareKeyAccount) else {
            _ = try ensureIdentity(authenticationContext: context)
            return try sign(message: message, context: context)
        }
        let key = try P256.Signing.PrivateKey(rawRepresentation: stored)
        let signature = try key.signature(for: data)
        return (signature.derRepresentation.base64EncodedString(), key.publicKey.x963Representation.base64EncodedString(), false)
    }

    private func saveKeychain(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "تعذر حفظ هوية الجهاز الآمنة"])
        }
    }

    private func loadKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? item as? Data : nil
    }
}
