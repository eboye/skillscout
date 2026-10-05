#if os(Linux)
import Foundation
import Glibc

/// Linux's Foundation has no `trashItem`, so this follows the freedesktop.org Trash spec, the one
/// GNOME Files and KDE read: the item moves into `Trash/files`, and a `.trashinfo` in `Trash/info`
/// remembers where it came from, so Restore puts it back.
extension FileManager {
  func trashItem(at url: URL, resultingItemURL: UnsafeMutablePointer<NSURL?>?) throws {
    let trashed = try FreedesktopTrash.move(url)
    resultingItemURL?.pointee = trashed as NSURL
  }
}

enum FreedesktopTrash {
  struct Failure: LocalizedError {
    let path: String
    let reason: String
    var errorDescription: String? { "Couldn't move \(path) to the Trash: \(reason)" }
  }

  /// The home Trash, under `$XDG_DATA_HOME`, or `~/.local/share` of `Paths.home`, so a made-up home
  /// gets its own Trash.
  static var homeTrash: URL {
    // A Flatpak's XDG_DATA_HOME is its own folder in ~/.var/app, so it uses the host's instead, as
    // long as that's in the same home: a made-up home gets its own Trash.
    let environment = ProcessInfo.processInfo.environment
    let data = Flatpak.isSandboxed
      ? environment["HOST_XDG_DATA_HOME"].flatMap { $0.hasPrefix(Paths.home.path + "/") ? $0 : nil }
      : environment["XDG_DATA_HOME"]
    if let data, data.hasPrefix("/") {
      return URL(fileURLWithPath: data, isDirectory: true).appending(path: "Trash")
    }
    return Paths.at(".local/share/Trash")
  }

  /// Moves the item itself, never what a link points to, and returns where it went.
  @discardableResult
  static func move(_ url: URL) throws -> URL {
    let path = url.standardizedFileURL.path
    var item = stat()
    guard lstat(path, &item) == 0 else { throw Failure(path: path, reason: String(cString: strerror(errno))) }

    let home = homeTrash
    var homeInfo = stat()
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    stat(home.path, &homeInfo)
    if item.st_dev == homeInfo.st_dev {
      return try move(path, into: home, infoPath: path)
    }
    // On another drive, the spec's trash is `.Trash-<uid>` at the top of that drive.
    let top = mountPoint(of: path, device: item.st_dev)
    let trash = URL(fileURLWithPath: top, isDirectory: true).appending(path: ".Trash-\(getuid())")
    let relative = String(path.dropFirst(top == "/" ? 1 : top.count + 1))
    return try move(path, into: trash, infoPath: relative)
  }

  private static func move(_ path: String, into trash: URL, infoPath: String) throws -> URL {
    let fm = FileManager.default
    let files = trash.appending(path: "files")
    let info = trash.appending(path: "info")
    try fm.createDirectory(at: files, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try fm.createDirectory(at: info, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

    let name = (path as NSString).lastPathComponent
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    let entry = "[Trash Info]\nPath=\(encode(infoPath))\nDeletionDate=\(deletionDate())\n"

    for attempt in 1...10_000 {
      let candidate = attempt == 1 ? name : ext.isEmpty || stem.isEmpty ? "\(name).\(attempt)" : "\(stem).\(attempt).\(ext)"
      let infoFile = info.appending(path: candidate + ".trashinfo").path
      // Creating the .trashinfo first, exclusively, claims the name before the item moves.
      let descriptor = open(infoFile, O_WRONLY | O_CREAT | O_EXCL, 0o600)
      if descriptor < 0 {
        if errno == EEXIST { continue }
        throw Failure(path: path, reason: String(cString: strerror(errno)))
      }
      let bytes = Array(entry.utf8)
      let written = write(descriptor, bytes, bytes.count)
      close(descriptor)
      let destination = files.appending(path: candidate)
      var existing = stat()
      // rename(2) replaces what's there, so a leftover file without its .trashinfo skips the name too.
      if lstat(destination.path, &existing) == 0 {
        unlink(infoFile)
        continue
      }
      guard written == bytes.count else {
        unlink(infoFile)
        throw Failure(path: path, reason: "couldn't write \(infoFile)")
      }
      guard rename(path, destination.path) == 0 else {
        let code = errno
        unlink(infoFile)
        throw Failure(path: path, reason: String(cString: strerror(code)))
      }
      return destination
    }
    throw Failure(path: path, reason: "the Trash has too many items called \(name)")
  }

  /// Walks up from the item until the device changes.
  private static func mountPoint(of path: String, device: dev_t) -> String {
    var current = (path as NSString).deletingLastPathComponent
    while current != "/" {
      let parent = (current as NSString).deletingLastPathComponent
      var info = stat()
      if stat(parent, &info) != 0 || info.st_dev != device { return current }
      current = parent
    }
    return "/"
  }

  /// Escapes the path like a URI path, keeping the slashes.
  private static func encode(_ path: String) -> String {
    var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
    allowed.insert(charactersIn: "-._~/")
    return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
  }

  /// Local time, without a time zone, as the spec asks.
  private static func deletionDate() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: .now)
  }
}
#endif
