import AppKit

/// Links the `skillscout` and `skillscoutctl` commands bundled in the app into /usr/local/bin.
enum CommandLineTool {
  static let commands = ["skillscout", "skillscoutctl"]
  static let folder = URL(fileURLWithPath: "/usr/local/bin")
  static let helpers = Bundle.main.bundleURL.appending(path: "Contents/Helpers")

  @MainActor
  static func install() {
    let fm = FileManager.default
    let missing = commands.filter { name in
      (try? fm.destinationOfSymbolicLink(atPath: folder.appending(path: name).path)) != helpers.appending(path: name).path
    }
    if missing.isEmpty {
      show("The skillscout command is already installed.", detail: "Run skillscout help in your terminal to see what it does.")
      return
    }

    do {
      for name in missing {
        let link = folder.appending(path: name)
        try? fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: helpers.appending(path: name))
      }
    } catch {
      let links = missing.map { "ln -sf '\(helpers.appending(path: $0).path)' '\(folder.appending(path: $0).path)'" }
      let command = (["mkdir -p '\(folder.path)'"] + links).joined(separator: " && ")
      var failure: NSDictionary?
      NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")?.executeAndReturnError(&failure)
      if let failure {
        if failure[NSAppleScript.errorNumber] as? Int == -128 { return }
        show("Couldn't install the command.", detail: failure[NSAppleScript.errorMessage] as? String ?? "")
        return
      }
    }
    show(
      "Installed the skillscout command.",
      detail: "Open a new terminal window and run skillscout help to get started. Agents can drive the app with skillscoutctl."
    )
  }

  @MainActor
  private static func show(_ message: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.runModal()
  }
}
