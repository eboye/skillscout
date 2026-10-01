import AppKit

/// Runs a `skillscoutctl` command on the store the window shows, and replies with JSON.
@MainActor
struct AppControl {
  let store: AppStore
  let request: Control.Request

  func reply() async -> Data {
    do {
      return Data(Control.ok.utf8) + (try await run())
    } catch {
      return Data((Control.failed + error.localizedDescription).utf8)
    }
  }

  /// The commands that answer before the app has read your skills and chats.
  private static let immediate: Set<String> = ["ping", "state", "screenshot", "window", "close", "quit"]

  private func run() async throws -> Data {
    if !Self.immediate.contains(request.command) { await store.waitUntilReady() }
    switch request.command {
    case "ping":
      return try encodeJSON(Ping(version: version, home: Paths.home.path, pid: ProcessInfo.processInfo.processIdentifier, ready: store.isReady))
    case "ready", "state": return try encodeJSON(state())
    case "list": return try list()
    case "show": return try show()
    case "similar": return try encodeJSON(store.pairs(plugins: true).map(pairJSON))
    case "suggestions": return try encodeJSON(store.suggestions.map(IdeaJSON.init))
    case "settings": return try await settings()
    case "screenshot": return try await screenshot()
    case "view": return try await navigate()
    case "open": return try await present()
    case "close": return try await closeAll()
    case "window": return try await resize()
    case "add": return try await add()
    case "uninstall": return try await uninstall()
    case "rename": return try await rename()
    case "edit": return try await edit()
    case "merge": return try await merge()
    case "dismiss": return try dismiss()
    case "explain": return try await explain()
    case "analyze": return try await analyze()
    case "draft": return try await draft()
    case "save": return try await save()
    case "refresh": return try await refresh()
    case "quit": return try quit()
    default: throw ControlError("There's no \(request.command) command. Run skillscoutctl help to see them all.")
    }
  }

  private var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
  }

  // MARK: - Looking

  private struct Ping: Encodable {
    let version: String
    let home: String
    let pid: Int32
    let ready: Bool
  }

  private struct State: Encodable {
    struct Selection: Encodable {
      var skill: String?
      var idea: String?
      var pair: [String]?
      var keep: String?
    }

    struct Presented: Encodable {
      let kind: String
      var skill: String?
      var message: String?
    }

    struct Status: Encodable {
      let messages: Int
      let days: Int
      let messagesByTool: [String: Int]
      let lastAnalysis: Date?
      let newSinceAnalysis: Int
    }

    struct Window: Encodable {
      let open: Bool
      let width: Int?
      let height: Int?
      let appearance: String
      let sheets: Int
      let settingsOpen: Bool
    }

    let version: String
    let home: String
    let ready: Bool
    let place: String
    let search: String
    let sort: String
    let plugins: Bool
    let selected: Selection?
    let listed: [String]
    let places: [String: Int]
    let presented: [Presented]
    let working: [String]
    let status: Status
    let window: Window
  }

  private func state() -> State {
    let place = store.place ?? .allSkills
    let listed: [String]
    let selected: State.Selection?
    switch place {
    case .suggestions:
      listed = store.listedSuggestions.map(\.name)
      selected = store.suggestion(store.selectedSuggestion).map { State.Selection(idea: $0.name) }
    case .similar:
      let pairs = store.listedPairs
      listed = pairs.map { "\($0.first) + \($0.second)" }
      selected = pairs.first { $0.id == store.selectedPair }.map { State.Selection(pair: [$0.first, $0.second], keep: store.keep(for: $0)) }
    default:
      listed = store.listedSkills.map(\.name)
      selected = store.skill(store.selectedSkill).map { State.Selection(skill: $0.name) }
    }

    let places: [SidebarItem] = [.allSkills, .missing, .unused] + store.tools.map(SidebarItem.tool) + [.suggestions, .similar]
    let main = mainWindow
    let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return State(
      version: version,
      home: Paths.home.path,
      ready: store.isReady,
      place: place.argument,
      search: store.search,
      sort: store.sort.rawValue,
      plugins: store.showPluginSkills,
      selected: selected,
      listed: listed,
      places: Dictionary(uniqueKeysWithValues: places.map { ($0.argument, store.count(in: $0)) }),
      presented: presented(),
      working: working(),
      status: State.Status(
        messages: store.prompts.count,
        days: UserDefaults.standard.integer(forKey: "lookbackDays"),
        messagesByTool: Dictionary(grouping: store.prompts, by: \.tool.rawValue).mapValues(\.count),
        lastAnalysis: store.lastAnalysis,
        newSinceAnalysis: store.newPromptCount
      ),
      window: State.Window(
        open: main != nil,
        width: main.map { Int($0.frame.width) },
        height: main.map { Int($0.frame.height) },
        appearance: dark ? "dark" : "light",
        sheets: main.map(WindowCapture.sheets)?.count ?? 0,
        settingsOpen: settingsWindow != nil
      )
    )
  }

  /// The sheets, dialogs and alerts the store keeps track of.
  private func presented() -> [State.Presented] {
    var presented: [State.Presented] = []
    if let skill = store.renaming { presented.append(.init(kind: "rename", skill: skill.name)) }
    if let skill = store.editing { presented.append(.init(kind: "edit", skill: skill.name)) }
    if let removal = store.removal {
      let kind = removal.copies.count == removal.skill.removableCopies.count ? "uninstall" : "remove"
      presented.append(.init(kind: kind, skill: removal.skill.name, message: "\(removal.title) \(removal.message(tools: store.tools))"))
    }
    if let error = store.errorMessage { presented.append(.init(kind: "alert", message: error)) }
    return presented
  }

  private func working() -> [String] {
    var working: [String] = []
    if store.isLoadingPrompts { working.append("Reading your chats") }
    if store.isAnalyzing { working.append("Finding repeated tasks") }
    for key in store.busy.sorted() {
      let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }
      switch parts[0] {
      case "explain":
        working.append("Explaining \(store.skills.first { $0.primary.contentHash == parts[1] }?.name ?? "a skill")")
      case "merge":
        let names = parts[1].split(separator: ">").map(String.init)
        working.append(names.count == 2 ? "Merging \(names[0]) into \(names[1])" : "Merging skills")
      case "draft":
        working.append("Drafting \(store.suggestions.first { $0.id.uuidString == parts[1] }?.name ?? "an idea")")
      default:
        working.append(key)
      }
    }
    return working
  }

  private func list() throws -> Data {
    let place = try option("in").map { value in
      guard let place = findPlace(value), place.listsSkills else {
        throw ControlError("--in takes all, missing, unused or a tool. For ideas and pairs, run skillscoutctl suggestions or similar.")
      }
      return place
    } ?? .allSkills
    let skills = store.skills(in: place, plugins: flag("plugins"), search: option("search") ?? "", sort: try sortOption() ?? .name)
    return try encodeJSON(skills.map(skillJSON))
  }

  private func show() throws -> Data {
    let skill = try findSkill(single("skill"))
    var json = skillJSON(skill)
    json.explanation = store.explanations[skill.primary.contentHash]
    json.text = try? String(contentsOf: skill.skillFile, encoding: .utf8)
    return try encodeJSON(json)
  }

  private func skillJSON(_ skill: Skill) -> SkillJSON {
    SkillJSON(skill, tools: store.tools, usage: store.usage[skill.id])
  }

  private struct PairJSON: Encodable {
    let skills: [String]
    let score: Double
    let sharedWords: [String]
    let keep: String
    let draft: String?
  }

  private func pairJSON(_ pair: SimilarPair) -> PairJSON {
    let keep = store.keep(for: pair)
    return PairJSON(
      skills: [pair.first, pair.second],
      score: (pair.score * 100).rounded() / 100,
      sharedWords: pair.sharedWords,
      keep: keep,
      draft: store.mergeDrafts[SkillInstaller.MergePlan.id(merging: pair.other(than: keep), into: keep)]
    )
  }

  private struct IdeaJSON: Encodable {
    struct Example: Encodable {
      let tool: String
      let project: String
      let date: Date
      let text: String
    }

    let name: String
    let title: String
    let summary: String
    let why: String
    let times: Int
    let projects: [String]
    let tools: [String]
    let examples: [Example]
    let draft: String?
    let savedTo: String?

    init(_ idea: Suggestion) {
      name = idea.name
      title = idea.title
      summary = idea.summary
      why = idea.why
      times = idea.examples.count
      projects = idea.projects
      tools = idea.tools.map(\.rawValue)
      examples = idea.examples.map { Example(tool: $0.tool.rawValue, project: $0.project, date: $0.date, text: $0.text) }
      draft = idea.draft
      savedTo = idea.savedTo
    }
  }

  private struct SettingsJSON: Encodable {
    let tools: [String: Bool]
    let engine: String
    let model: String
    let days: Int
    let autoAnalyze: Bool
    let threshold: Int
  }

  private func settings() async throws -> Data {
    if !arguments.isEmpty {
      guard arguments.count == 2 else { throw ControlError("Pass a setting and its value, like: skillscoutctl settings days 90") }
      try await change(arguments[0], to: arguments[1])
    }
    let defaults = UserDefaults.standard
    let engine = AIEngine.current
    return try encodeJSON(SettingsJSON(
      tools: Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0.rawValue, store.tools.contains($0)) }),
      engine: engine.kind.rawValue,
      model: engine.model,
      days: defaults.integer(forKey: "lookbackDays"),
      autoAnalyze: defaults.bool(forKey: "autoAnalyze"),
      threshold: defaults.integer(forKey: "autoThreshold")
    ))
  }

  private func change(_ key: String, to value: String) async throws {
    let defaults = UserDefaults.standard
    if let tool = Tool(argument: key) {
      store.setTool(tool, enabled: try onOff(value, key))
      return
    }
    switch key.lowercased() {
    case "engine":
      guard let kind = AIEngineKind(rawValue: value.lowercased()) else { throw ControlError("engine takes codex or claude.") }
      defaults.set(kind.rawValue, forKey: "engine")
    case "model":
      guard !value.isEmpty else { throw ControlError("model takes the name of a model.") }
      defaults.set(value, forKey: AIEngine.current.kind.modelKey)
    case "days":
      guard let days = Int(value), [30, 60, 90, 180].contains(days) else { throw ControlError("days takes 30, 60, 90 or 180.") }
      defaults.set(days, forKey: "lookbackDays")
      await store.refreshPrompts()
    case "auto-analyze":
      defaults.set(try onOff(value, key), forKey: "autoAnalyze")
    case "threshold":
      guard let count = Int(value), (10...500).contains(count) else { throw ControlError("threshold takes a number from 10 to 500.") }
      defaults.set(count, forKey: "autoThreshold")
    default:
      throw ControlError("There's no \(key) setting. Use a tool, engine, model, days, auto-analyze or threshold.")
    }
  }

  private struct Shot: Encodable {
    let file: String
    let width: Int
    let height: Int
  }

  private func screenshot() async throws -> Data {
    let window: NSWindow
    switch option("window") ?? "main" {
    case "main":
      window = try await ensureMainWindow()
    case "settings":
      guard let settings = settingsWindow else { throw ControlError("The Settings window isn't open. Run skillscoutctl open settings first.") }
      window = settings
    default:
      throw ControlError("--window takes main or settings.")
    }

    let image = try WindowCapture.image(of: window)
    let file = arguments.first.map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.temporaryDirectory.appending(path: "skillscout-\(Int(Date.now.timeIntervalSince1970 * 1000)).png")
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
      throw ControlError("Couldn't turn the window into a PNG.")
    }
    try png.write(to: file)
    return try encodeJSON(Shot(file: file.path, width: image.width, height: image.height))
  }

  // MARK: - Moving around

  private func navigate() async throws -> Data {
    var items = arguments[...]
    if let first = items.first, let place = findPlace(first) {
      if case .tool(let tool) = place, !store.tools.contains(tool) {
        throw ControlError("\(tool.name) is off. Turn it on with: skillscoutctl settings \(tool.rawValue) on")
      }
      store.place = place
      items.removeFirst()
    }
    if let search = option("search") { store.search = search }
    if let sort = try sortOption() { store.sort = sort }
    if let plugins = option("plugins") { store.showPluginSkills = try onOff(plugins, "--plugins") }

    let place = store.place ?? .allSkills
    switch place {
    case .suggestions:
      guard items.count <= 1 else { throw ControlError("Pick one idea.") }
      if let name = items.first { store.selectedSuggestion = try findIdea(name).id }
    case .similar:
      guard items.isEmpty || items.count == 2 else {
        throw ControlError("Pick a pair with its two skills, like: skillscoutctl view similar writing-style email-style")
      }
      if let first = items.first, let second = items.last {
        let id = SimilarPair.key(try findSkill(first).id, try findSkill(second).id)
        guard store.listedPairs.contains(where: { $0.id == id }) else {
          throw ControlError("\(first) and \(second) aren't a pair in Similar skills. Run skillscoutctl similar to see the pairs.")
        }
        store.selectedPair = id
      }
    default:
      guard items.count <= 1 else { throw ControlError("Pick one skill.") }
      if let name = items.first {
        let skill = try findSkill(name)
        guard store.listedSkills.contains(where: { $0.id == skill.id }) else {
          if !skill.isPersonal, !store.showPluginSkills {
            throw ControlError("\(skill.name) comes from a plugin or a tool. Add --plugins on to list those skills.")
          }
          throw ControlError("\(skill.name) isn't listed in \(place.argument)\(store.search.isEmpty ? "" : " with the search \(store.search)").")
        }
        store.selectedSkill = skill.id
      }
    }
    _ = try await ensureMainWindow()
    await settle()
    return try encodeJSON(state())
  }

  private func present() async throws -> Data {
    guard let what = arguments.first else {
      throw ControlError("Tell me what to open: rename, edit, uninstall, settings, finder, editor or updates.")
    }
    func target() throws -> Skill {
      guard arguments.count == 2 else { throw ControlError("Tell me which skill, like: skillscoutctl open \(what) writing-style") }
      return try findSkill(arguments[1])
    }

    switch what {
    case "rename", "edit", "uninstall":
      let skill = try target()
      guard skill.isPersonal else { throw SkillInstaller.leftAlone(skill) }
      let copies = try SkillInstaller.removal(of: skill, from: try option("from").map(findTool))
      _ = try await ensureMainWindow()
      if !presented().isEmpty {
        dismissPresented()
        await settle()
      }
      switch what {
      case "rename": store.renaming = skill
      case "edit": store.editing = skill
      default: store.removal = Removal(skill: skill, copies: copies)
      }
    case "settings":
      guard let showSettings = store.showSettings else { throw ControlError("Settings can't open until the window has.") }
      showSettings()
    case "finder":
      Finder.reveal(try target().primary.folder)
    case "editor":
      Finder.open(try target().skillFile)
    case "updates":
      AppUpdater.shared.checkForUpdates()
    default:
      throw ControlError("I can open rename, edit, uninstall, settings, finder, editor or updates.")
    }
    await settle()
    return try encodeJSON(state())
  }

  private func closeAll() async throws -> Data {
    dismissPresented()
    settingsWindow?.close()
    await settle()
    return try encodeJSON(state())
  }

  private func dismissPresented() {
    store.renaming = nil
    store.editing = nil
    store.removal = nil
    store.errorMessage = nil
  }

  private func resize() async throws -> Data {
    let window = try await ensureMainWindow()
    if let size = option("size") {
      let sides = size.lowercased().split(separator: "x").compactMap { Double($0) }
      guard sides.count == 2, sides.allSatisfy({ $0 >= 400 && $0 <= 4000 }) else {
        throw ControlError("--size takes a width and a height in points, like 1180x760.")
      }
      let top = window.frame.maxY
      window.setContentSize(NSSize(width: sides[0], height: sides[1]))
      window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }
    if let appearance = option("appearance") {
      switch appearance {
      case "light": NSApp.appearance = NSAppearance(named: .aqua)
      case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
      case "system": NSApp.appearance = nil
      default: throw ControlError("--appearance takes light, dark or system.")
      }
    }
    await settle()
    return try encodeJSON(state())
  }

  // MARK: - Changing

  private struct Added: Encodable {
    let tool: String
    let path: String
    let copied: Bool
  }

  private struct AddResult: Encodable {
    let skill: String
    let added: [Added]
    let availableIn: [String]
  }

  private func add() async throws -> Data {
    let skill = try findSkill(single("skill"))
    let targets: [Tool]
    if flag("all") {
      targets = skill.missing(from: store.tools)
    } else if let value = option("to") {
      targets = [try findTool(value)]
    } else {
      throw ControlError("Pick where to add it: --to <tool>, or --all for every tool that's missing it.")
    }

    var covered = skill.availableIn
    var added: [Added] = []
    for tool in targets where !covered.contains(tool) {
      let destination = try await store.add(skill, to: tool)
      covered.formUnion(SkillRoot.all.first { $0.url == tool.skillsFolder }?.readBy ?? [tool])
      added.append(Added(tool: tool.rawValue, path: destination.path, copied: skill.isPluginOnly))
    }
    return try encodeJSON(AddResult(skill: skill.name, added: added, availableIn: availableIn(skill.id)))
  }

  private struct Removed: Encodable {
    let skill: String
    let trashed: [String]
    let linkTargetsKept: [String]
    let toolsLosing: [String]
    let availableIn: [String]
  }

  private func uninstall() async throws -> Data {
    let skill = try findSkill(single("skill"))
    let copies = try SkillInstaller.removal(of: skill, from: try option("from").map(findTool))
    try await store.remove(copies)
    return try encodeJSON(Removed(
      skill: skill.name,
      trashed: copies.map(\.folder.path),
      linkTargetsKept: skill.linkTargetsKept(copies).map(\.path),
      toolsLosing: store.tools.filter(skill.toolsLosing(copies).contains).map(\.rawValue),
      availableIn: availableIn(skill.id)
    ))
  }

  private func availableIn(_ id: Skill.ID) -> [String] {
    guard let skill = store.skill(id) else { return [] }
    return store.tools.filter(skill.availableIn.contains).map(\.rawValue)
  }

  private func rename() async throws -> Data {
    guard arguments.count == 2 else {
      throw ControlError("Pass the skill and its new name, like: skillscoutctl rename release-notes changelog")
    }
    let skill = try personalSkill(arguments[0])
    try await store.rename(skill, to: arguments[1])
    guard let renamed = store.skill(arguments[1]) else {
      throw ControlError("Renamed \(skill.name), but Skillscout can't find \(arguments[1]) now. Run skillscoutctl refresh.")
    }
    return try encodeJSON(skillJSON(renamed))
  }

  private struct Edited: Encodable {
    let skill: String
    let changed: Bool
    let files: [String]
    let otherFiles: [String]
  }

  private func edit() async throws -> Data {
    let skill = try personalSkill(single("skill"))
    guard let text = request.input else {
      throw ControlError("Pass the new SKILL.md with --file <path>, or with --file - on stdin.")
    }
    let edit = try SkillInstaller.edit(skill)
    let changed = text != edit.original
    if changed { try await store.save(edit, text: text, overwrite: false) }
    return try encodeJSON(Edited(skill: skill.name, changed: changed, files: edit.files.map(\.path), otherFiles: edit.otherFiles.map(\.path)))
  }

  private struct MergeResult: Encodable {
    let keep: String
    let other: String
    let merged: Bool
    let changes: String
    var draft: String?
    var skill: SkillJSON?
  }

  private func merge() async throws -> Data {
    guard arguments.count == 2 else {
      throw ControlError("Pass the skill to keep, then the one to merge into it, like: skillscoutctl merge writing-style email-style")
    }
    let kept = try personalSkill(arguments[0])
    let other = try personalSkill(arguments[1])
    guard kept.id != other.id else { throw ControlError("Pick two different skills.") }
    let plan = try SkillInstaller.planMerge(other, into: kept)
    store.mergeKeep[SimilarPair.key(kept.id, other.id)] = kept.id

    if let text = request.input {
      store.mergeDrafts[plan.id] = text
    } else {
      await wait(for: "merge:\(plan.id)")
      if store.mergeDrafts[plan.id] == nil || flag("fresh") { try await store.draftMerge(plan) }
    }

    let changes = plan.message(tools: store.tools)
    if flag("draft") {
      return try encodeJSON(MergeResult(keep: kept.name, other: other.name, merged: false, changes: changes, draft: store.mergeDrafts[plan.id]))
    }
    try await store.merge(plan)
    return try encodeJSON(MergeResult(keep: kept.name, other: other.name, merged: true, changes: changes, skill: store.skill(kept.id).map(skillJSON)))
  }

  private func dismiss() throws -> Data {
    switch arguments.count {
    case 1:
      let idea = try findIdea(arguments[0])
      store.dismiss(idea.id)
      return try encodeJSON(["dismissed": [idea.name]])
    case 2:
      let id = SimilarPair.key(try findSkill(arguments[0]).id, try findSkill(arguments[1]).id)
      guard let pair = store.similar.first(where: { $0.id == id }) else {
        throw ControlError("\(arguments[0]) and \(arguments[1]) aren't a similar pair. Run skillscoutctl similar to see the pairs.")
      }
      store.dismissPair(pair)
      return try encodeJSON(["dismissed": [pair.first, pair.second]])
    default:
      throw ControlError("Pass an idea, or the two skills of a similar pair.")
    }
  }

  private func explain() async throws -> Data {
    let skill = try findSkill(single("skill"))
    let key = skill.primary.contentHash
    if flag("fresh") { store.explanations[key] = nil }
    await wait(for: "explain:\(key)")
    if store.explanations[key] == nil { try await store.explain(skill) }
    return try encodeJSON(["skill": skill.name, "explanation": store.explanations[key] ?? ""])
  }

  private func analyze() async throws -> Data {
    guard !store.prompts.isEmpty else {
      throw ControlError("There are no messages from the last \(UserDefaults.standard.integer(forKey: "lookbackDays")) days to look at.")
    }
    if store.isAnalyzing {
      while store.isAnalyzing { try? await Task.sleep(for: .milliseconds(500)) }
    } else {
      try await store.analyze()
    }
    return try encodeJSON(store.suggestions.map(IdeaJSON.init))
  }

  private func draft() async throws -> Data {
    let idea = try findIdea(single("idea"))
    if let saved = idea.savedTo {
      throw ControlError("\(idea.name) is saved already, in \(Paths.abbreviate(URL(fileURLWithPath: saved))).")
    }
    if let text = request.input {
      store.updateDraft(idea.id, text)
    } else {
      await wait(for: "draft:\(idea.id)")
      if store.suggestion(idea.id)?.draft == nil || flag("fresh") { try await store.draft(idea.id) }
    }
    guard let drafted = store.suggestion(idea.id) else { throw ControlError("\(idea.name) went away while drafting.") }
    return try encodeJSON(IdeaJSON(drafted))
  }

  private func save() async throws -> Data {
    let idea = try findIdea(single("idea"))
    if let saved = idea.savedTo {
      throw ControlError("\(idea.name) is saved already, in \(Paths.abbreviate(URL(fileURLWithPath: saved))).")
    }
    guard idea.draft != nil else {
      throw ControlError("\(idea.name) has no draft yet. Write one with: skillscoutctl draft \(idea.name)")
    }
    let target: SaveTarget = try option("to").map { .tool(try findTool($0)) } ?? .everywhere(store.tools)
    let folder = try await store.save(idea.id, to: target)
    return try encodeJSON(["idea": idea.name, "savedTo": folder.path])
  }

  private func refresh() async throws -> Data {
    await store.refreshSkills()
    await store.refreshPrompts()
    return try encodeJSON(state())
  }

  private func quit() throws -> Data {
    Task {
      try? await Task.sleep(for: .milliseconds(300))
      NSApp.terminate(nil)
    }
    return try encodeJSON(["quitting": true])
  }

  // MARK: - Arguments

  private var arguments: [String] { request.arguments }

  private func option(_ name: String) -> String? { request.options[name] }

  private func flag(_ name: String) -> Bool { request.options[name] != nil }

  private func single(_ what: String) throws -> String {
    guard arguments.count == 1 else {
      throw ControlError(arguments.isEmpty
        ? "Tell me which \(what). Run skillscoutctl help \(request.command) for an example."
        : "Pass one \(what) at a time.")
    }
    return arguments[0]
  }

  private func findSkill(_ name: String) throws -> Skill {
    if let skill = store.skills.first(where: { $0.name == name }) ?? store.skills.first(where: { $0.name.lowercased() == name.lowercased() }) {
      return skill
    }
    let close = store.skills.map(\.name).filter { $0.localizedCaseInsensitiveContains(name) }.sorted().prefix(5)
    if close.isEmpty { throw ControlError("There's no skill called \(name). Run skillscoutctl list to see them all.") }
    throw ControlError("There's no skill called \(name). Did you mean \(close.formatted(.list(type: .or)))?")
  }

  private func personalSkill(_ name: String) throws -> Skill {
    let skill = try findSkill(name)
    guard skill.isPersonal else { throw SkillInstaller.leftAlone(skill) }
    return skill
  }

  private func findIdea(_ name: String) throws -> Suggestion {
    let key = name.lowercased()
    if let idea = store.suggestions.first(where: { [$0.name.lowercased(), $0.title.lowercased(), $0.id.uuidString.lowercased()].contains(key) }) {
      return idea
    }
    throw ControlError("There's no idea called \(name). Run skillscoutctl suggestions to see them.")
  }

  private func findTool(_ value: String) throws -> Tool {
    guard let tool = Tool(argument: value) else {
      throw ControlError("\(value) isn't a tool I know. Use one of: \(Tool.allCases.map(\.rawValue).joined(separator: ", ")).")
    }
    return tool
  }

  private func findPlace(_ value: String) -> SidebarItem? {
    switch value.lowercased() {
    case "all": .allSkills
    case "missing": .missing
    case "unused": .unused
    case "suggestions", "ideas": .suggestions
    case "similar": .similar
    default: Tool(argument: value).map(SidebarItem.tool)
    }
  }

  private func sortOption() throws -> SkillSort? {
    guard let value = option("sort") else { return nil }
    guard let sort = SkillSort(rawValue: value) else { throw ControlError("--sort takes newest, name or use.") }
    return sort
  }

  private func onOff(_ value: String, _ name: String) throws -> Bool {
    switch value.lowercased() {
    case "on", "true", "yes", "1": return true
    case "off", "false", "no", "0": return false
    default: throw ControlError("\(name) takes on or off.")
    }
  }

  // MARK: - Windows

  private var mainWindow: NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
  }

  private var settingsWindow: NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true && $0.isVisible }
  }

  private func ensureMainWindow() async throws -> NSWindow {
    if let mainWindow { return mainWindow }
    store.showWindow?()
    await settle()
    guard let mainWindow else { throw ControlError("The Skillscout window is closed, and it didn't open again.") }
    return mainWindow
  }

  /// Gives SwiftUI time to draw a change, and a sheet time to slide in or out.
  private func settle() async {
    try? await Task.sleep(for: .milliseconds(500))
  }

  private func wait(for busyKey: String) async {
    while store.busy.contains(busyKey) {
      try? await Task.sleep(for: .milliseconds(200))
    }
  }
}

extension SidebarItem {
  /// The name `skillscoutctl` uses for the place.
  var argument: String {
    switch self {
    case .allSkills: "all"
    case .missing: "missing"
    case .unused: "unused"
    case .tool(let tool): tool.rawValue
    case .suggestions: "suggestions"
    case .similar: "similar"
    }
  }
}

/// Draws a window the way it looks now, with no screen recording permission, since it's the app's own.
@MainActor
enum WindowCapture {
  static func sheets(of window: NSWindow) -> [NSWindow] {
    var sheets: [NSWindow] = []
    var next = window.attachedSheet
    while let sheet = next {
      sheets.append(sheet)
      next = sheet.attachedSheet
    }
    return sheets
  }

  /// The window with its sheets, dialogs and alerts on top.
  static func image(of window: NSWindow) throws -> CGImage {
    let scale = window.backingScaleFactor
    let frame = window.frame
    guard let base = snapshot(window),
          let context = CGContext(
            data: nil, width: Int(frame.width * scale), height: Int(frame.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { throw ControlError("Couldn't draw the window.") }

    context.draw(base, in: CGRect(x: 0, y: 0, width: frame.width * scale, height: frame.height * scale))
    for sheet in sheets(of: window) {
      guard let image = snapshot(sheet) else { continue }
      let rect = CGRect(
        x: (sheet.frame.minX - frame.minX) * scale, y: (sheet.frame.minY - frame.minY) * scale,
        width: sheet.frame.width * scale, height: sheet.frame.height * scale
      )
      context.draw(image, in: rect)
    }
    guard let image = context.makeImage() else { throw ControlError("Couldn't draw the window.") }
    return image
  }

  private static func snapshot(_ window: NSWindow) -> CGImage? {
    guard let view = window.contentView?.superview ?? window.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage
  }
}
