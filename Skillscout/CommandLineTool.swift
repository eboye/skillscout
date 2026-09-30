import AppKit

/// Links the `skillscout` command bundled in the app into /usr/local/bin.
enum CommandLineTool {
  static let link = URL(fileURLWithPath: "/usr/local/bin/skillscout")
  static let bundled = Bundle.main.bundleURL.appending(path: "Contents/Helpers/skillscout")

  @MainActor
  static func install() {
    let fm = FileManager.default
    if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == bundled.path {
      show("The skillscout command is already installed.", detail: "Run skillscout help in your terminal to see what it does.")
      return
    }

    do {
      try? fm.removeItem(at: link)
      try fm.createSymbolicLink(at: link, withDestinationURL: bundled)
    } catch {
      let command = "mkdir -p /usr/local/bin && ln -sf '\(bundled.path)' '\(link.path)'"
      var failure: NSDictionary?
      NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")?.executeAndReturnError(&failure)
      if let failure {
        if failure[NSAppleScript.errorNumber] as? Int == -128 { return }
        show("Couldn't install the command.", detail: failure[NSAppleScript.errorMessage] as? String ?? "")
        return
      }
    }
    show("Installed the skillscout command.", detail: "Open a new terminal window and run skillscout help to get started.")
  }

  @MainActor
  private static func show(_ message: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.runModal()
  }
}
