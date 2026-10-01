import Foundation

/// How `skillscoutctl` talks to the running app: one request per connection, on a Unix socket.
/// The command writes a JSON request and closes its side. The app replies with `ok` and JSON,
/// or `error` and a message.
enum Control {
  /// In your private temporary folder, so only you can connect. The name comes from the home folder,
  /// so a test copy of the app on a made-up home gets a socket of its own.
  static let socketPath: String = {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    let folder = length > 0 ? buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : NSTemporaryDirectory()
    let home = Paths.home.resolvingSymlinksInPath().path
    return URL(fileURLWithPath: folder).appending(path: "skillscout-\(shortHash(home)).sock").path
  }()

  struct Request: Codable, Sendable {
    var command: String
    var arguments: [String] = []
    var options: [String: String] = [:]
    /// The text of `--file`. The command reads it, so paths stay relative to where it ran.
    var input: String?
  }

  static let ok = "ok\n"
  static let failed = "error\n"

  static func address(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
      throw ControlError("The socket path is too long: \(path)")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return address
  }

  /// A connection to the app, or nil when no app listens.
  static func connection(to path: String = socketPath) -> Int32? {
    guard var address = try? address(path) else { return nil }
    let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard socket >= 0 else { return nil }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0 else {
      close(socket)
      return nil
    }
    ignoreSigpipe(socket)
    return socket
  }

  /// Writing to a socket the other side closed fails, instead of ending the process.
  static func ignoreSigpipe(_ socket: Int32) {
    var on: Int32 = 1
    setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
  }

  static func readAll(_ socket: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
      let count = read(socket, &buffer, buffer.count)
      if count < 0, errno == EINTR { continue }
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }

  @discardableResult
  static func writeAll(_ socket: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let written = write(socket, bytes.baseAddress! + offset, bytes.count - offset)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else { return false }
        offset += written
      }
      return true
    }
  }
}

struct ControlError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
