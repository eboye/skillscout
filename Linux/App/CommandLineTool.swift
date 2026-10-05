import Foundation

/// The Linux side of CommandLineTool.swift: links the `skillscout` command next to the app into
/// ~/.local/bin, which is on the PATH of most distributions and needs no password.
enum CommandLineTool {
  static var link: URL { Paths.at(".local/bin/skillscout") }

  static var bundled: URL? {
    let folder = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    let command = folder.appending(path: "skillscout")
    return FileManager.default.isExecutableFile(atPath: command.path) ? command : nil
  }

  /// What happened, for the alert.
  static func install() -> String {
    if Flatpak.isSandboxed { return installFlatpakWrapper() }
    guard let bundled else {
      return "Couldn't find the skillscout command next to the app. Build it with swift build, or install the package, which puts it in /usr/bin."
    }
    if let installed = ShellEnvironment.find("skillscout", in: ProcessInfo.processInfo.environment["PATH"] ?? ""),
       installed.resolvingSymlinksInPath() == bundled.resolvingSymlinksInPath() {
      return "The skillscout command is already installed at \(Paths.abbreviate(installed))."
    }

    let fm = FileManager.default
    do {
      try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
      if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
        try fm.removeItem(at: link)
      } else if fm.fileExists(atPath: link.path) {
        return "\(Paths.abbreviate(link)) already exists and isn't a link, so Skillscout left it alone."
      }
      try fm.createSymbolicLink(at: link, withDestinationURL: bundled)
    } catch {
      return "Couldn't install the command: \(error.localizedDescription)"
    }
    return installed()
  }

  /// A link would point inside the sandbox, so the Flatpak writes a script that runs the command
  /// through flatpak run instead.
  private static func installFlatpakWrapper() -> String {
    let fm = FileManager.default
    let id = ProcessInfo.processInfo.environment["FLATPAK_ID"] ?? "com.flaviocopes.skillscout"
    let script = "#!/bin/sh\n# Runs the skillscout command from the Skillscout Flatpak.\nexec flatpak run --command=skillscout \(id) \"$@\"\n"
    if fm.fileExists(atPath: link.path) || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
      let current = (try? String(contentsOf: link, encoding: .utf8)) ?? ""
      guard current.contains("flatpak run --command=skillscout") else {
        return "\(Paths.abbreviate(link)) already exists, so Skillscout left it alone."
      }
    }
    do {
      try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
      try script.write(to: link, atomically: true, encoding: .utf8)
      try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: link.path)
    } catch {
      return "Couldn't install the command: \(error.localizedDescription)"
    }
    return installed()
  }

  private static func installed() -> String {
    let onPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { $0 == link.deletingLastPathComponent().path }
    return "Installed skillscout in \(Paths.abbreviate(link.deletingLastPathComponent()))."
      + (onPath ? " Open a new terminal and run skillscout." : " Add ~/.local/bin to your PATH to run it.")
  }
}
