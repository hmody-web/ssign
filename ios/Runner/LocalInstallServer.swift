import Foundation
import Darwin

/// Lightweight loopback server used only to stream a validly signed IPA back to iOS OTA installer.
/// The manifest itself must be fetched over trusted HTTPS, so the server exposes only the IPA on 127.0.0.1.
final class LocalInstallServer {
  private let queue = DispatchQueue(label: "sign.local-install", qos: .userInitiated)
  private var listener: Int32 = -1
  private(set) var port: UInt16 = 0
  private var ipaURL: URL?
  private var running = false
  private let stateLock = NSLock()
  private var downloadStarted = false

  deinit { stop() }

  func start(ipa: URL) throws -> UInt16 {
    stop()
    stateLock.lock()
    downloadStarted = false
    stateLock.unlock()
    ipaURL = ipa
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw posix("socket") }
    var one: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) { p in
      p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bound == 0 else { close(fd); throw posix("bind") }
    guard listen(fd, 8) == 0 else { close(fd); throw posix("listen") }

    var actual = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &actual) { p in
      p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
    }
    guard named == 0 else { close(fd); throw posix("getsockname") }
    port = UInt16(bigEndian: actual.sin_port)
    listener = fd; running = true
    queue.async { [weak self] in self?.acceptLoop(fd) }
    return port
  }

  func stop() {
    running = false
    if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1 }
  }

  var ipaHTTPURL: String { "http://127.0.0.1:\(port)/app.ipa" }

  var hasStartedDownload: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return downloadStarted
  }

  private func acceptLoop(_ fd: Int32) {
    while running {
      let client = accept(fd, nil, nil)
      if client < 0 { if running { usleep(50000) }; continue }
      handle(client)
    }
  }

  private func handle(_ fd: Int32) {
    defer { close(fd) }
    var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
    while data.count < 65536 {
      let n = recv(fd, &buf, buf.count, 0); if n <= 0 { return }
      data.append(contentsOf: buf[0..<n])
      if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
    }
    guard let request = String(data: data, encoding: .utf8), let first = request.components(separatedBy: "\r\n").first else { return }
    let parts = first.split(separator: " ")
    guard parts.count >= 2, (parts[0] == "GET" || parts[0] == "HEAD"), parts[1].split(separator:"?").first == "/app.ipa", let file = ipaURL else {
      sendHeader(fd, status:"404 Not Found", length:0, contentRange:nil); return
    }
    let headOnly = parts[0] == "HEAD"
    if !headOnly {
      stateLock.lock()
      downloadStarted = true
      stateLock.unlock()
    }
    let attrs = try? FileManager.default.attributesOfItem(atPath:file.path)
    let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    let rangeLine = request.components(separatedBy:"\r\n").first { $0.lowercased().hasPrefix("range:") }
    var start: UInt64 = 0; var end: UInt64 = size > 0 ? size - 1 : 0; var partial = false
    if let line = rangeLine, let spec = line.split(separator:":",maxSplits:1).last?.trimmingCharacters(in:.whitespaces), spec.lowercased().hasPrefix("bytes=") {
      let r = String(spec.dropFirst(6)).split(separator:"-",maxSplits:1,omittingEmptySubsequences:false)
      if r.count == 2, let s = UInt64(r[0]) { start=s; if !r[1].isEmpty, let e=UInt64(r[1]) { end=min(e,end) }; partial=true }
    }
    guard size > 0, start < size, end >= start else { sendHeader(fd,status:"416 Range Not Satisfiable",length:0,contentRange:"bytes */\(size)"); return }
    let length = end - start + 1
    sendHeader(fd,status:partial ? "206 Partial Content":"200 OK",length:length,contentRange:partial ? "bytes \(start)-\(end)/\(size)":nil)
    if headOnly { return }
    guard let h = try? FileHandle(forReadingFrom:file) else { return }
    defer { try? h.close() }; try? h.seek(toOffset:start)
    var left=length
    while left>0 {
      let chunk=h.readData(ofLength:Int(min(left,UInt64(1024*512))))
      guard !chunk.isEmpty else { break }
      guard sendAll(fd,chunk) else { break }
      left -= UInt64(chunk.count)
    }
  }

  private func sendHeader(_ fd:Int32,status:String,length:UInt64,contentRange:String?) {
    var h="HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(length)\r\nAccept-Ranges: bytes\r\n"
    if let contentRange { h += "Content-Range: \(contentRange)\r\n" }
    h += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    _ = sendAll(fd,Data(h.utf8))
  }

  private func sendAll(_ fd:Int32,_ data:Data)->Bool {
    var sent=0; var ok=true
    data.withUnsafeBytes { raw in
      guard let base=raw.baseAddress else { ok=false; return }
      while sent<data.count { let n=send(fd,base.advanced(by:sent),data.count-sent,0); if n<=0 {ok=false;return}; sent+=n }
    }
    return ok
  }

  private func posix(_ operation:String)->NSError { NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSLocalizedDescriptionKey:"\(operation) failed (errno \(errno))"]) }
}
