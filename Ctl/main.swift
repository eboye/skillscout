import AppKit

/// A command `skillscoutctl` knows, with its options, for checking arguments and for help.
struct Spec {
  enum Group: String, CaseIterable {
    case look = "Look"
    case move = "Move around"
    case change = "Change"
    case app = "App"
  }

  let name: String
  let usage: String
  let summary: String
  let group: Group
  var valued: [String] = []
  var flags: [String] = []
  var details: String?

  static let all: [Spec] = [
    Spec(name: "ping", usage: "ping", summary: "Whether the app runs on this home folder, and its version", group: .look,
         details: "Answers right away, even while the app reads your chats. Fails when the app isn't running, and doesn't start it."),
    Spec(name: "ready", usage: "ready", summary: "Wait until the app has read your skills and chats, then print its state", group: .look),
    Spec(name: "state", usage: "state", summary: "What the window shows: the place, the selection, the list, sheets and alerts", group: .look,
         details: "Prints the sidebar place, the search, the sort, the selected skill, idea or pair, the names listed, the count of every place, the sheets and alerts on screen, what AI is working on, the chats read, and the window's size and appearance."),
    Spec(name: "list", usage: "list [--in <place>] [--search <text>] [--sort <order>] [--plugins]", summary: "The skills in a place, as JSON", group: .look,
         valued: ["in", "search", "sort"], flags: ["plugins"],
         details: "A place is all, missing, unused or a tool. The sort is newest, name or use. --plugins adds plugin and built-in skills. It doesn't change the window."),
    Spec(name: "show", usage: "show <skill>", summary: "Everything about a skill, with its SKILL.md and explanation", group: .look),
    Spec(name: "similar", usage: "similar", summary: "The pairs of skills that read alike, and the merge drafts", group: .look),
    Spec(name: "suggestions", usage: "suggestions", summary: "The skill ideas, with their example messages and drafts", group: .look),
    Spec(name: "screenshot", usage: "screenshot [file.png] [--window main|settings]", summary: "Save a PNG of the window, with its sheets and alerts", group: .look,
         valued: ["window"],
         details: "Draws the app's own window, so it needs no screen recording permission and works while the window is behind others. Without a file, it saves to a temporary file. Prints the path and the size in pixels."),

    Spec(name: "view", usage: "view [place] [skill | idea | skill skill] [--search <text>] [--sort <order>] [--plugins on|off]", summary: "Show a place in the sidebar and select an item", group: .move,
         valued: ["search", "sort", "plugins"],
         details: "Places are all, missing, unused, a tool, suggestions and similar. After the place, name a skill to select it, an idea in suggestions, or the two skills of a pair in similar. Without a place, it selects in the place shown now. --search \"\" clears the search. Prints the state."),
    Spec(name: "open", usage: "open rename|edit|uninstall <skill> [--from <tool>] | open settings|updates | open finder|editor <skill>", summary: "Open a sheet, Settings, or a skill in Finder or your editor", group: .move,
         valued: ["from"],
         details: "rename, edit and uninstall open the same sheets as the buttons, so you can take a screenshot of them. They change nothing until you confirm in the window. Use the add, rename, edit and uninstall commands to make the change directly."),
    Spec(name: "close", usage: "close", summary: "Close the sheets, alerts and the Settings window", group: .move),
    Spec(name: "window", usage: "window [--size <width>x<height>] [--appearance light|dark|system]", summary: "Resize the window, or switch it to light or dark", group: .move,
         valued: ["size", "appearance"]),

    Spec(name: "add", usage: "add <skill> --to <tool> | --all", summary: "Add a skill to another tool", group: .change,
         valued: ["to"], flags: ["all"],
         details: "Links the skill folder into the tool's skills folder. Plugin skills get copied instead."),
    Spec(name: "uninstall", usage: "uninstall <skill> [--from <tool>]", summary: "Move a skill to the Trash, from every tool or one", group: .change,
         valued: ["from"]),
    Spec(name: "rename", usage: "rename <skill> <new-name>", summary: "Give a skill a new name", group: .change),
    Spec(name: "edit", usage: "edit <skill> --file <path | ->", summary: "Replace a skill's SKILL.md", group: .change,
         valued: ["file"],
         details: "Writes the text into every copy of the SKILL.md that has the same text now. Keep the name in the frontmatter, and use rename to change it. --file - reads the text from stdin."),
    Spec(name: "merge", usage: "merge <skill> <other> [--file <path | ->] [--draft] [--fresh]", summary: "Merge a skill into another, with AI or with your SKILL.md", group: .change,
         valued: ["file"], flags: ["draft", "fresh"],
         details: "Keeps the first skill and moves the other one to the Trash. Without --file, AI writes the merged SKILL.md, or the app uses the draft it already has. --draft only writes the draft, so you can read it in the window or with similar. --fresh asks AI again."),
    Spec(name: "dismiss", usage: "dismiss <idea> | dismiss <skill> <skill>", summary: "Hide a skill idea, or a pair of similar skills", group: .change),
    Spec(name: "explain", usage: "explain <skill> [--fresh]", summary: "Ask AI what a skill does", group: .change,
         flags: ["fresh"]),
    Spec(name: "analyze", usage: "analyze", summary: "Ask AI for skill ideas from your recent messages", group: .change),
    Spec(name: "draft", usage: "draft <idea> [--file <path | ->] [--fresh]", summary: "Write the SKILL.md of an idea, with AI or with your text", group: .change,
         valued: ["file"], flags: ["fresh"]),
    Spec(name: "save", usage: "save <idea> [--to <tool>]", summary: "Save an idea's draft as a skill, for every tool or one", group: .change,
         valued: ["to"]),
    Spec(name: "settings", usage: "settings [<setting> <value>]", summary: "Print the settings, or change one", group: .change,
         details: "Settings: a tool name with on or off, engine codex or claude, model <name>, days 30, 60, 90 or 180, auto-analyze on or off, and threshold, from 10 to 500."),

    Spec(name: "launch", usage: "launch [--app <path>]", summary: "Start the app, wait until it's ready, and print its state", group: .app,
         valued: ["app"],
         details: "Starts the app that contains this command, or the one you pass with --app. Other commands start it too when it isn't running. With $HOME set to a made-up home folder, it starts a separate copy of the app on that home, as long as the copy has its own bundle ID, like the one scripts/test-app.sh builds."),
    Spec(name: "refresh", usage: "refresh", summary: "Read your skills and chats again", group: .app),
    Spec(name: "quit", usage: "quit", summary: "Quit the app", group: .app),
    Spec(name: "help", usage: "help [command]", summary: "Show this help, or a command's", group: .app),
  ]

  static func named(_ name: String) -> Spec? { all.first { $0.name == name } }
}

struct UsageError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct Failure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

let mainBundleID = "com.flaviocopes.skillscout"

var version: String {
  Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

func printHelp(_ spec: Spec?) {
  guard let spec else {
    print("skillscoutctl drives the running Skillscout app, so agents can do what you do in its window.")
    print("Every command prints JSON. Errors go to stderr, with exit code 1.")
    print()
    print("Usage: skillscoutctl <command> [arguments] [options]")
    for group in Spec.Group.allCases {
      print()
      print("\(group.rawValue):")
      for spec in Spec.all where spec.group == group {
        print("  \(spec.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(spec.summary)")
      }
    }
    print()
    print("Run skillscoutctl help <command> to see its arguments.")
    print("Tools: \(Tool.allCases.map(\.rawValue).joined(separator: ", "))")
    return
  }
  print("Usage: skillscoutctl \(spec.usage)")
  print()
  print(spec.summary + ".")
  if let details = spec.details {
    print()
    print(details)
  }
}

struct Parsed {
  var spec: Spec
  var request: Control.Request
  var help = false
}

@MainActor
func parse(_ raw: [String]) throws -> Parsed? {
  var queue = raw[...]
  guard let name = queue.popFirst(), !["-h", "--help"].contains(name) else { return nil }
  if name == "--version" {
    print("skillscoutctl \(version)")
    exit(0)
  }
  guard let spec = Spec.named(name) else { throw UsageError(message: "There's no \(name) command.") }

  var parsed = Parsed(spec: spec, request: Control.Request(command: name))
  while let argument = queue.popFirst() {
    if argument == "-h" || argument == "--help" {
      parsed.help = true
    } else if argument.hasPrefix("--"), argument.count > 2 {
      var key = String(argument.dropFirst(2))
      var value: String?
      if let equals = key.firstIndex(of: "=") {
        value = String(key[key.index(after: equals)...])
        key = String(key[..<equals])
      }
      if spec.valued.contains(key) {
        guard let value = value ?? queue.popFirst() else { throw UsageError(message: "--\(key) needs a value.") }
        parsed.request.options[key] = value
      } else if spec.flags.contains(key), value == nil {
        parsed.request.options[key] = ""
      } else {
        throw UsageError(message: "\(name) doesn't take --\(key).")
      }
    } else {
      parsed.request.arguments.append(argument)
    }
  }

  if let file = parsed.request.options.removeValue(forKey: "file") {
    parsed.request.input = try read(file)
  }
  if name == "screenshot", let file = parsed.request.arguments.first {
    parsed.request.arguments[0] = absolute(file)
  }
  if let app = parsed.request.options["app"] {
    parsed.request.options["app"] = absolute(app)
  }
  return parsed
}

func read(_ file: String) throws -> String {
  if file == "-" {
    return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
  }
  do {
    return try String(contentsOf: URL(fileURLWithPath: absolute(file)), encoding: .utf8)
  } catch {
    throw Failure(message: "Couldn't read \(file): \(error.localizedDescription)")
  }
}

func absolute(_ path: String) -> String {
  let expanded = (path as NSString).expandingTildeInPath
  return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL.path
}

/// Sends a request and returns the app's JSON, or nil when no app listens on this home folder.
func send(_ request: Control.Request) throws -> String? {
  guard let socket = Control.connection() else { return nil }
  defer { close(socket) }
  guard Control.writeAll(socket, try JSONEncoder().encode(request)) else {
    throw Failure(message: "Skillscout closed the connection before reading the command.")
  }
  shutdown(socket, SHUT_WR)
  let reply = String(decoding: Control.readAll(socket), as: UTF8.self)
  if reply.hasPrefix(Control.ok) { return String(reply.dropFirst(Control.ok.count)) }
  if reply.hasPrefix(Control.failed) { throw Failure(message: String(reply.dropFirst(Control.failed.count))) }
  throw Failure(message: "Skillscout closed the connection without an answer.")
}

/// The home folder macOS gave you, as opposed to `$HOME`.
var realHome: String {
  guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return NSHomeDirectory() }
  return String(cString: directory)
}

var onRealHome: Bool {
  Paths.home.resolvingSymlinksInPath().path == URL(fileURLWithPath: realHome).resolvingSymlinksInPath().path
}

/// The app to start: the one you pass, the one that contains this command, or the installed one.
func appToLaunch(_ path: String?) throws -> URL {
  if let path {
    guard Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier != nil else { throw Failure(message: "\(path) isn't an app.") }
    return URL(fileURLWithPath: path)
  }
  let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: absolute(CommandLine.arguments[0]))
  let app = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  if app.pathExtension == "app" { return app }
  if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainBundleID) { return installed }
  throw Failure(message: "Couldn't find Skillscout. Pass it with: skillscoutctl launch --app /path/to/Skillscout.app")
}

@MainActor
func launch(_ path: String?) async throws {
  let app = try appToLaunch(path)
  let bundleID = Bundle(url: app)?.bundleIdentifier ?? ""
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = false
  configuration.addsToRecentItems = false

  if !onRealHome {
    guard bundleID != mainBundleID else {
      throw Failure(message: "$HOME is \(Paths.home.path), a made-up home. Skillscout would share its settings with the real app there, so start a test copy with its own bundle ID: scripts/test-app.sh builds one.")
    }
    configuration.environment = ["HOME": Paths.home.path]
    configuration.createsNewApplicationInstance = true
  } else if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) {
    throw Failure(message: "Skillscout is running, but it doesn't answer. It may be older than skillscoutctl. Quit it and try again.")
  }

  let running = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
  let deadline = Date.now.addingTimeInterval(30)
  while Date.now < deadline {
    if (try? send(Control.Request(command: "ping"))) != nil { return }
    if running.isTerminated { throw Failure(message: "Skillscout quit right after it started.") }
    try await Task.sleep(for: .milliseconds(200))
  }
  throw Failure(message: "Skillscout started, but didn't answer within 30 seconds.")
}

func output(_ json: String) {
  print(json.hasSuffix("\n") ? json.dropLast() : json[...])
}

do {
  guard let parsed = try parse(Array(CommandLine.arguments.dropFirst())) else {
    printHelp(nil)
    exit(0)
  }
  let request = parsed.request
  if parsed.help {
    printHelp(parsed.spec)
    exit(0)
  }

  switch request.command {
  case "help":
    guard let name = request.arguments.first else {
      printHelp(nil)
      break
    }
    guard let spec = Spec.named(name) else { throw UsageError(message: "There's no \(name) command.") }
    printHelp(spec)
  case "launch":
    if (try send(Control.Request(command: "ping"))) == nil { try await launch(request.options["app"]) }
    output(try send(Control.Request(command: "ready")) ?? "")
  case "ping":
    guard let json = try send(request) else {
      throw Failure(message: "Skillscout isn't running on \(Paths.abbreviate(Paths.home)). Start it with: skillscoutctl launch")
    }
    output(json)
  case "quit":
    output(try send(request) ?? "{\n  \"quitting\" : false\n}")
  default:
    if let json = try send(request) {
      output(json)
    } else {
      try await launch(nil)
      guard let json = try send(request) else { throw Failure(message: "Skillscout stopped answering.") }
      output(json)
    }
  }
} catch let error as UsageError {
  FileHandle.standardError.write(Data("skillscoutctl: \(error.message)\nRun skillscoutctl help for usage.\n".utf8))
  exit(2)
} catch {
  FileHandle.standardError.write(Data("skillscoutctl: \(error.localizedDescription)\n".utf8))
  exit(1)
}
