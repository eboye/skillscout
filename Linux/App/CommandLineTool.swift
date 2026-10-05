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
      if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
        _ = existing
        try fm.removeItem(at: link)
      } else if fm.fileExists(atPath: link.path) {
        return "\(Paths.abbreviate(link)) already exists and isn't a link, so Skillscout left it alone."
      }
      try fm.createSymbolicLink(at: link, withDestinationURL: bundled)
    } catch {
      return "Couldn't install the command: \(error.localizedDescription)"
    }
    let onPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { $0 == link.deletingLastPathComponent().path }
    return "Installed skillscout in \(Paths.abbreviate(link.deletingLastPathComponent()))."
      + (onPath ? " Open a new terminal and run skillscout." : " Add ~/.local/bin to your PATH to run it.")
  }
}
