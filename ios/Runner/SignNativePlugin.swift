import Flutter
import UIKit
import Security
import ZIPFoundation
import ZSign

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
    case "signIpa":
      DispatchQueue.global(qos: .userInitiated).async {
        do { let output = try self.signIpa(args); DispatchQueue.main.async { result(output) } }
        catch { DispatchQueue.main.async { result(FlutterError(code:"SIGN_FAILED",message:error.localizedDescription,details:nil)) } }
      }
    case "shareFile": share(args, result: result)
    case "installIpa": install(args, result: result)
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
        let temp=try self.extractIPA(URL(fileURLWithPath:path), prefix:"inspect")
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
    let ipa=recoverDocumentPath(str("ipaPath"))
    let p12=recoverDocumentPath(str("p12Path"))
    let provision=recoverDocumentPath(str("provisionPath"))
    let password=str("p12Password")
    let fm = FileManager.default
    guard fm.fileExists(atPath: ipa) else {
      throw NSError(domain:"Sign",code:1,userInfo:[NSLocalizedDescriptionKey:"IPA file is missing"])
    }
    guard fm.fileExists(atPath: p12) else {
      throw NSError(domain:"Sign",code:2,userInfo:[NSLocalizedDescriptionKey:"P12 certificate file is missing"])
    }
    guard fm.fileExists(atPath: provision) else {
      throw NSError(domain:"Sign",code:3,userInfo:[NSLocalizedDescriptionKey:"Provisioning profile file is missing"])
    }
    let root=try extractIPA(URL(fileURLWithPath:ipa),prefix:"sign")
    defer {try? FileManager.default.removeItem(at:root)}
    let app=try findApp(in:root)
    try updateInfoPlist(app:app,bundleId:"",displayName:"",version:str("version"),build:str("build"),removeDevices:(args["removeSupportedDevices"] as? Bool) ?? false)
    let requestedIcon = str("iconPath")
    if !requestedIcon.isEmpty { try replaceAppIcons(app: app, iconPath: requestedIcon) }
    // ZSignApple SignFolder expects the extracted IPA root that CONTAINS Payload, not Payload itself.
    let signingRoot = root.path
    let requestedBundle = str("bundleId")
    let requestedName = str("displayName")
    let code = signingRoot.withCString { cPath in
      p12.withCString { cCert in
        p12.withCString { cKey in
          provision.withCString { cProv in
            password.withCString { cPassword in
              requestedBundle.withCString { cBundle in
                requestedName.withCString { cName in
                  zsign(cPath, cCert, cKey, cProv, cPassword, cBundle, cName)
                }
              }
            }
          }
        }
      }
    }
    guard code==0 else {throw NSError(domain:"Sign",code:Int(code),userInfo:[NSLocalizedDescriptionKey:"zsign returned code \(code)"])}
    let docs=try FileManager.default.url(for:.documentDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
    let outDir=docs.appendingPathComponent("Signed",isDirectory:true); try FileManager.default.createDirectory(at:outDir,withIntermediateDirectories:true)
    let base=URL(fileURLWithPath:ipa).deletingPathExtension().lastPathComponent.replacingOccurrences(of:" ",with:"_")
    let out=outDir.appendingPathComponent("\(base)-signed-\(Int(Date().timeIntervalSince1970)).ipa")
    if FileManager.default.fileExists(atPath:out.path){try FileManager.default.removeItem(at:out)}
    try FileManager.default.zipItem(at:root,to:out,shouldKeepParent:false,compressionMethod:.deflate)
    return out.path
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
      let rendered = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
      guard let data = rendered.pngData() else { continue }
      try data.write(to: target, options: .atomic)
    }
  }

  private func updateInfoPlist(app:URL,bundleId:String,displayName:String,version:String,build:String,removeDevices:Bool) throws {
    let url=app.appendingPathComponent("Info.plist")
    let data=try Data(contentsOf:url)
    var obj=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] ?? [:]
    if !bundleId.isEmpty {obj["CFBundleIdentifier"]=bundleId}
    if !displayName.isEmpty {obj["CFBundleDisplayName"]=displayName;obj["CFBundleName"]=displayName}
    if !version.isEmpty {obj["CFBundleShortVersionString"]=version}
    if !build.isEmpty {obj["CFBundleVersion"]=build}
    if removeDevices {obj.removeValue(forKey:"UIDeviceFamily");obj.removeValue(forKey:"UIRequiredDeviceCapabilities")}
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

  private func install(_ args:[String:Any], result:@escaping FlutterResult) {
    guard let rawPath=args["path"] as? String else { result(FlutterError(code:"BAD_PATH",message:"Missing IPA path",details:nil)); return }
    let path = recoverDocumentPath(rawPath)
    let ipa=URL(fileURLWithPath:path)
    guard FileManager.default.fileExists(atPath:ipa.path) else { result(FlutterError(code:"NOT_FOUND",message:"Signed IPA not found",details:nil)); return }
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        let root=try self.extractIPA(ipa,prefix:"install-info"); defer {try? FileManager.default.removeItem(at:root)}
        let app=try self.findApp(in:root); let data=try Data(contentsOf:app.appendingPathComponent("Info.plist"))
        let info=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] ?? [:]
        let bundle=info["CFBundleIdentifier"] as? String ?? "app.sign.install"
        let version=info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "1.0"
        let title=info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "App"
        DispatchQueue.main.async {
          do {
            _ = try self.installServer.start(ipa:ipa)
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
