import Dispatch
import Foundation
import Glibc

/// The Linux side of FileWatcher.swift: inotify watches on every folder under the paths, since
/// inotify isn't recursive like FSEvents. New folders get a watch as they appear, and the changed
/// paths reach the handler in one batch, `latency` seconds after the first change.
final class FileWatcher: @unchecked Sendable {
  private let handler: @Sendable ([String]) -> Void
  private let latency: TimeInterval
  private let queue = DispatchQueue(label: "com.flaviocopes.skillscout.watcher")
  private let descriptor: Int32
  private var source: DispatchSourceRead?
  private var folders: [Int32: String] = [:]
  private var pending: Set<String> = []
  private var flushScheduled = false

  /// Hidden folders, apart from Codex's skills/.system, and these hold caches and dependencies, never skills or chats.
  private static let skipped: Set<String> = ["node_modules", "__pycache__", "venv", "extensions"]
  private static let maxWatches = 50_000
  private static let mask = UInt32(IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE | IN_ATTRIB | IN_DELETE_SELF)

  init(paths: [String], latency: TimeInterval = 2, handler: @escaping @Sendable ([String]) -> Void) {
    self.handler = handler
    self.latency = latency
    descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
    guard descriptor >= 0 else { return }

    queue.async { [self] in
      for path in paths { watchTree(path) }
      let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
      source.setEventHandler { [weak self] in self?.read() }
      source.resume()
      self.source = source
    }
  }

  deinit {
    source?.cancel()
    if descriptor >= 0 { close(descriptor) }
  }

  private func watchTree(_ path: String) {
    guard folders.count < Self.maxWatches else { return }
    let watch = inotify_add_watch(descriptor, path, Self.mask)
    guard watch >= 0 else { return }
    folders[watch] = path

    guard let directory = opendir(path) else { return }
    defer { closedir(directory) }
    while let entry = readdir(directory) {
      // Links to skill folders get a watch, but the walk doesn't follow them, so it can't loop.
      let type = entry.pointee.d_type
      let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
      guard name != ".", name != ".." else { continue }
      let child = path + "/" + name
      if type == UInt8(DT_DIR) {
        guard !Self.skipped.contains(name), !name.hasPrefix(".") || name == ".system" else { continue }
        watchTree(child)
      } else if type == UInt8(DT_LNK) {
        var info = stat()
        if stat(child, &info) == 0, info.st_mode & S_IFMT == S_IFDIR {
          let linked = inotify_add_watch(descriptor, child, Self.mask)
          if linked >= 0 { folders[linked] = child }
        }
      }
    }
  }

  private func read() {
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = buffer.withUnsafeMutableBytes { Glibc.read(descriptor, $0.baseAddress, $0.count) }
      guard count > 0 else { break }
      var offset = 0
      while offset < count {
        let (watch, mask, length, name) = buffer.withUnsafeBytes { bytes -> (Int32, UInt32, Int, String) in
          let event = bytes.loadUnaligned(fromByteOffset: offset, as: inotify_event.self)
          let start = offset + MemoryLayout<inotify_event>.size
          let raw = bytes[start..<(start + Int(event.len))]
          return (event.wd, event.mask, Int(event.len), String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self))
        }
        offset += MemoryLayout<inotify_event>.size + length
        handle(watch: watch, mask: mask, name: name)
      }
    }
  }

  private func handle(watch: Int32, mask: UInt32, name: String) {
    if mask & UInt32(IN_Q_OVERFLOW) != 0 {
      // Too many changes to list, so report every folder and let the store look again.
      pending.formUnion(folders.values.map { $0 + "/" })
    } else if mask & UInt32(IN_IGNORED) != 0 {
      folders[watch] = nil
      return
    } else if let folder = folders[watch] {
      let path = name.isEmpty ? folder : folder + "/" + name
      pending.insert(path)
      if mask & UInt32(IN_ISDIR) != 0, mask & UInt32(IN_CREATE | IN_MOVED_TO) != 0 {
        watchTree(path)
      }
    }
    scheduleFlush()
  }

  private func scheduleFlush() {
    guard !flushScheduled, !pending.isEmpty else { return }
    flushScheduled = true
    queue.asyncAfter(deadline: .now() + latency) { [weak self] in
      guard let self else { return }
      let changed = Array(pending)
      pending = []
      flushScheduled = false
      handler(changed)
    }
  }
}
