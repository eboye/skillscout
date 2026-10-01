import AppKit

/// Listens on `Control.socketPath`, so `skillscoutctl` can drive the app.
enum ControlServer {
  @MainActor private static var listener: Listener?

  @MainActor
  static func start(store: AppStore) {
    guard listener == nil else { return }
    do {
      listener = try Listener(path: Control.socketPath) { request in
        await AppControl(store: store, request: request).reply()
      }
    } catch {
      NSLog("Skillscout can't listen for skillscoutctl: %@", error.localizedDescription)
    }
  }
}

private final class Listener {
  private let socket: Int32
  private let source: DispatchSourceRead

  init(path: String, handle: @escaping @Sendable (Control.Request) async -> Data) throws {
    if let other = Control.connection(to: path) {
      close(other)
      throw ControlError("Another Skillscout on this home folder already listens on \(path).")
    }
    unlink(path)

    var address = try Control.address(path)
    let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard socket >= 0, bound == 0, chmod(path, 0o600) == 0, listen(socket, 16) == 0 else {
      let reason = String(cString: strerror(errno))
      close(socket)
      throw ControlError("Couldn't listen on \(path): \(reason)")
    }
    self.socket = socket

    source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: DispatchQueue(label: "skillscout.control"))
    source.setEventHandler {
      let client = accept(socket, nil, nil)
      guard client >= 0 else { return }
      Control.ignoreSigpipe(client)
      var timeout = timeval(tv_sec: 10, tv_usec: 0)
      setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
      DispatchQueue.global().async {
        let data = Control.readAll(client)
        Task {
          let reply = if let request = try? JSONDecoder().decode(Control.Request.self, from: data) {
            await handle(request)
          } else {
            Data((Control.failed + "Skillscout couldn't read the request.").utf8)
          }
          DispatchQueue.global().async {
            Control.writeAll(client, reply)
            close(client)
          }
        }
      }
    }
    source.resume()

    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
      unlink(path)
    }
  }
}
