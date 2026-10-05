#if os(Linux)
import Foundation

/// Inside a Flatpak, the agents' CLIs and the user's login shell live on the host, outside the
/// sandbox. These run them there with flatpak-spawn, which the manifest allows by talking to
/// org.freedesktop.Flatpak. Outside a Flatpak, nothing here changes anything.
enum Flatpak {
  /// Checked before any host command runs, so the first check also moves the temporary folder
  /// somewhere the host can see, for the app and the command alike.
  static let isSandboxed: Bool = {
    let sandboxed = ProcessInfo.processInfo.environment["FLATPAK_ID"] != nil
    if sandboxed { shareTemporaryFolder() }
    return sandboxed
  }()
  private static let spawn = URL(fileURLWithPath: "/usr/bin/flatpak-spawn")

  /// Makes a configured process run on the host: same command, arguments, folder and PATH.
  /// The standard input, output and error files go along, since flatpak-spawn forwards them.
  static func runOnHost(_ process: Process) {
    guard isSandboxed, let executable = process.executableURL else { return }
    var arguments = ["--host", "--watch-bus"]
    if let folder = process.currentDirectoryURL { arguments.append("--directory=\(folder.path)") }
    if let path = process.environment?["PATH"] { arguments.append("--env=PATH=\(path)") }
    // The same home as the app's, so the login shell reads the same profile and finds the same CLIs.
    arguments.append("--env=HOME=\(Paths.home.path)")
    process.arguments = arguments + [executable.path] + (process.arguments ?? [])
    process.executableURL = spawn
  }

  /// Looks for a command on the host's PATH, since the sandbox can't see /usr/bin and friends there.
  static func find(_ name: String, in path: String) -> URL? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "command -v \"$0\"", name]
    // flatpak-spawn itself needs the session bus from the environment, so only PATH changes.
    process.environment = ProcessInfo.processInfo.environment.merging(["PATH": path]) { $1 }
    runOnHost(process)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let found = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return process.terminationStatus == 0 && found.hasPrefix("/") ? URL(fileURLWithPath: found) : nil
  }

  /// The sandbox's /tmp is its own, so files the host CLIs read and write go in the app's cache
  /// folder, ~/.var/app/<id>/cache, which has the same path on both sides.
  private static func shareTemporaryFolder() {
    guard let cache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] else { return }
    let folder = URL(fileURLWithPath: cache).appending(path: "tmp")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    setenv("TMPDIR", folder.path, 1)
  }
}
#endif
