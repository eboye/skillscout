import Foundation
import Observation

/// A place in the sidebar.
enum SidebarItem: Hashable {
  case allSkills
  case missing
  case unused
  case tool(Tool)
  case suggestions
  case similar

  var listsSkills: Bool { self != .suggestions && self != .similar }
}

@MainActor
@Observable
final class AppStore {
  var skills: [Skill] = []
  var prompts: [Prompt] = []
  var usage: [Skill.ID: SkillUsage] = [:]
  /// The tools you use, in `Tool.allCases` order. Skillscout ignores the others.
  var tools: [Tool] = Tool.enabled
  var suggestions: [Suggestion] = []
  var explanations: [String: String] = [:]
  var dismissed: [String] = []
  /// Pairs of your skills that read alike, most alike first.
  var similar: [SimilarPair] = []
  /// The pairs you said aren't alike, by `SimilarPair.id`.
  var dismissedPairs: [String] = []
  /// Merged SKILL.md drafts, by `MergePlan.id`.
  var mergeDrafts: [String: String] = [:]
  var analyzedIDs: Set<String> = []
  var lastAnalysis: Date?

  /// True once the first scan of your skills and chats is done.
  var isReady = false
  var isLoadingPrompts = false
  var isAnalyzing = false
  var busy: Set<String> = []
  var errorMessage: String?
  var searchRequests = 0
  /// Copies waiting for you to confirm, before they go to the Trash.
  var removal: Removal?
  /// The skill whose new name you're typing.
  var renaming: Skill?
  var editing: Skill?

  // The window: what it shows and what's selected, so `skillscoutctl` can drive it too.
  var place: SidebarItem? = .allSkills
  var selectedSkill: Skill.ID?
  var selectedSuggestion: Suggestion.ID?
  var selectedPair: SimilarPair.ID?
  var search = ""
  var sort = SkillSort(rawValue: UserDefaults.standard.string(forKey: "skillSort") ?? "") ?? .newest {
    didSet { UserDefaults.standard.set(sort.rawValue, forKey: "skillSort") }
  }
  var showPluginSkills = UserDefaults.standard.bool(forKey: "showPluginSkills") {
    didSet { UserDefaults.standard.set(showPluginSkills, forKey: "showPluginSkills") }
  }
  /// The skill each similar pair keeps when you merge it, once you pick one.
  var mergeKeep: [SimilarPair.ID: Skill.ID] = [:]
  /// The window's actions for opening Settings and the main window again.
  @ObservationIgnored var showSettings: (() -> Void)?
  @ObservationIgnored var showWindow: (() -> Void)?

  @ObservationIgnored private let library = PromptLibrary()
  @ObservationIgnored private var allPrompts: [Prompt] = []
  @ObservationIgnored private var uses: [SkillUse] = []
  @ObservationIgnored private var watcher: FileWatcher?
  @ObservationIgnored private var started = false
  @ObservationIgnored private var skillsDirty = false
  @ObservationIgnored private var promptsDirty = false
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var lastAutoAttempt: Date?

  private let stateFile = Paths.stateFile

  var newPromptCount: Int {
    prompts.count(where: { !analyzedIDs.contains($0.id) })
  }

  func skill(_ id: Skill.ID?) -> Skill? {
    skills.first { $0.id == id }
  }

  func suggestion(_ id: Suggestion.ID?) -> Suggestion? {
    suggestions.first { $0.id == id }
  }

  // MARK: - Loading

  func start() async {
    guard !started else { return }
    started = true
    UserDefaults.standard.register(defaults: ["lookbackDays": 60, "autoAnalyze": true, "autoThreshold": 40])
    loadState()
    await refreshSkills()
    await refreshPrompts()

    let folders = [".agents", ".config/agents"] + Tool.allCases.flatMap(\.homeFolders)
    let paths = folders.map { Paths.at($0).path }.filter { FileManager.default.fileExists(atPath: $0) }
    watcher = FileWatcher(paths: paths) { [weak self] changed in
      Task { @MainActor in self?.handle(changed) }
    }
  }

  func waitUntilReady() async {
    while !isReady {
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  func setTool(_ tool: Tool, enabled: Bool) {
    tools = Tool.allCases.filter { $0 == tool ? enabled : tools.contains($0) }
    UserDefaults.standard.set(tools.map(\.rawValue), forKey: "tools")
    if case .tool(let shown) = place, !tools.contains(shown) { place = .allSkills }
    applyTools()
  }

  func refreshSkills() async {
    let dismissed = Set(dismissedPairs)
    (skills, similar) = await Task.detached {
      let skills = SkillScanner.scan()
      return (skills, SkillSimilarity.pairs(in: skills, dismissed: dismissed))
    }.value
    applyTools()
  }

  func refreshPrompts() async {
    isLoadingPrompts = true
    (allPrompts, uses) = await library.load(lookbackDays: UserDefaults.standard.integer(forKey: "lookbackDays"))
    applyTools()
    isLoadingPrompts = false
    isReady = true
    Task { await maybeAnalyzeAutomatically() }
  }

  private func applyTools() {
    let enabled = Set(tools)
    prompts = allPrompts.filter { enabled.contains($0.tool) }
    usage = SkillUsage.tally(uses.filter { enabled.contains($0.tool) }, skills: skills, aliases: SkillAliases.load())
  }

  private static let chatFolders = [
    "/agent-transcripts/", "/.codex/sessions/", "/.codex/archived_sessions/", "/.claude/projects/",
    "/.gemini/tmp/", "/.factory/sessions/", "/.pi/agent/sessions/", "/.local/share/amp/threads/", "/.local/share/opencode/opencode.db",
  ]

  private func handle(_ changed: [String]) {
    for path in changed {
      if Self.chatFolders.contains(where: path.contains) || path.hasSuffix("/.claude/history.jsonl") {
        promptsDirty = true
      } else if path.contains("/skills") || path.contains("/plugins/cache/") || path.contains("/plugins/local/")
        || path.hasSuffix("/.claude/settings.json") {
        skillsDirty = true
      }
    }
    guard skillsDirty || promptsDirty, refreshTask == nil else { return }

    refreshTask = Task {
      while skillsDirty || promptsDirty {
        try? await Task.sleep(for: .seconds(3))
        let (doSkills, doPrompts) = (skillsDirty, promptsDirty)
        skillsDirty = false
        promptsDirty = false
        if doSkills { await refreshSkills() }
        if doPrompts { await refreshPrompts() }
      }
      refreshTask = nil
    }
  }

  // MARK: - What the window lists

  /// The skills that the tools you use load: yours, and plugin and built-in ones when `plugins` is on.
  func library(plugins: Bool) -> [Skill] {
    let enabled = Set(tools)
    return skills.filter { (plugins || $0.isPersonal) && !$0.availableIn.isDisjoint(with: enabled) }
  }

  func isMissing(_ skill: Skill) -> Bool {
    skill.isPersonal && !skill.missing(from: tools).isEmpty
  }

  /// The skills a place in the sidebar lists, matching `search`, in `sort` order.
  func skills(in place: SidebarItem, plugins: Bool, search: String = "", sort: SkillSort = .name) -> [Skill] {
    filtered(place, plugins: plugins, search: search).sorted { sort.inOrder($0, $1) { usage[$0.id] } }
  }

  /// The number next to a place in the sidebar.
  func count(in place: SidebarItem) -> Int {
    switch place {
    case .suggestions: suggestions.count
    case .similar: listedPairs.count
    default: filtered(place, plugins: showPluginSkills, search: "").count
    }
  }

  private func filtered(_ place: SidebarItem, plugins: Bool, search: String) -> [Skill] {
    var skills = library(plugins: plugins)
    switch place {
    case .missing: skills = skills.filter(isMissing)
    case .unused: skills = skills.filter { usage[$0.id] == nil }
    case .tool(let tool): skills = skills.filter { $0.availableIn.contains(tool) }
    default: break
    }
    guard !search.isEmpty else { return skills }
    return skills.filter {
      $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
    }
  }

  func pairs(plugins: Bool, search: String = "") -> [SimilarPair] {
    let listed = Set(library(plugins: plugins).map(\.id))
    return similar.filter { pair in
      listed.contains(pair.first) && listed.contains(pair.second)
        && (search.isEmpty || pair.first.localizedCaseInsensitiveContains(search) || pair.second.localizedCaseInsensitiveContains(search))
    }
  }

  var listedSkills: [Skill] {
    skills(in: place ?? .allSkills, plugins: showPluginSkills, search: search, sort: sort)
  }

  var listedPairs: [SimilarPair] {
    pairs(plugins: showPluginSkills, search: search)
  }

  var listedSuggestions: [Suggestion] {
    guard !search.isEmpty else { return suggestions }
    return suggestions.filter {
      $0.title.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search)
    }
  }

  /// The selected skill, when it's yours to edit, rename or uninstall.
  var actionSkill: Skill? {
    guard place?.listsSkills ?? true, let skill = skill(selectedSkill), skill.isPersonal else { return nil }
    return skill
  }

  /// The skill a merge keeps: the one you picked, or else the one you use more, or the one more tools load.
  func keep(for pair: SimilarPair) -> Skill.ID {
    if let picked = mergeKeep[pair.id] { return picked }
    func weight(_ id: Skill.ID) -> (Int, Int) { (usage[id]?.chats ?? 0, skill(id)?.availableIn.count ?? 0) }
    return weight(pair.second) > weight(pair.first) ? pair.second : pair.first
  }

  /// Selects a skill, and switches to All skills when the window shows ideas or pairs.
  func reveal(_ id: Skill.ID) {
    if !(place?.listsSkills ?? false) { place = .allSkills }
    selectedSkill = id
  }

  // MARK: - Actions

  /// Runs a button's action, and shows what went wrong in an alert.
  func perform(_ action: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await action()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func analyze() async throws {
    guard !isAnalyzing, !prompts.isEmpty else { return }
    isAnalyzing = true
    defer { isAnalyzing = false }

    let found = try await Analyzer.findSuggestions(prompts: prompts, skills: skills, dismissed: dismissed, engine: .current)
    let skillNames = Set(skills.map(\.name))
    let kept = suggestions.filter { $0.draft != nil && $0.savedTo == nil }
    let fresh = found.filter { candidate in
      !skillNames.contains(candidate.name) && !dismissed.contains(candidate.name) && !kept.contains { $0.name == candidate.name }
    }
    suggestions = kept + fresh
    analyzedIDs = Set(prompts.map(\.id))
    lastAnalysis = .now
    saveState()
  }

  private func maybeAnalyzeAutomatically() async {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "autoAnalyze"),
          lastAnalysis != nil,
          newPromptCount >= defaults.integer(forKey: "autoThreshold"),
          lastAutoAttempt.map({ Date.now.timeIntervalSince($0) > 1800 }) ?? true
    else { return }
    lastAutoAttempt = .now
    do {
      try await analyze()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func explain(_ skill: Skill) async throws {
    let key = skill.primary.contentHash
    let busyKey = "explain:\(key)"
    guard explanations[key] == nil, !busy.contains(busyKey) else { return }
    let text = try String(contentsOf: skill.skillFile, encoding: .utf8)

    busy.insert(busyKey)
    defer { busy.remove(busyKey) }
    explanations[key] = try await Analyzer.explain(name: skill.name, skillText: text, engine: .current)
    saveState()
  }

  @discardableResult
  func add(_ skill: Skill, to tool: Tool) async throws -> URL {
    let destination = try SkillInstaller.add(skill, to: tool)
    await refreshSkills()
    return destination
  }

  func remove(_ copies: [SkillCopy]) async throws {
    do {
      try SkillInstaller.remove(copies)
    } catch {
      await refreshSkills()
      throw error
    }
    await refreshSkills()
  }

  func rename(_ skill: Skill, to name: String) async throws {
    do {
      try SkillInstaller.rename(skill, to: name, among: skills)
    } catch {
      await refreshSkills()
      throw error
    }
    await refreshSkills()
    reveal(name)
  }

  /// The editor catches the error itself, so it stays open with your text.
  func save(_ edit: SkillInstaller.Edit, text: String, overwrite: Bool) async throws {
    try SkillInstaller.save(edit, text: text, overwrite: overwrite)
    await refreshSkills()
  }

  func dismissPair(_ pair: SimilarPair) {
    dismissedPairs.append(pair.id)
    similar.removeAll { $0.id == pair.id }
    saveState()
  }

  @discardableResult
  func draftMerge(_ plan: SkillInstaller.MergePlan) async throws -> String {
    let busyKey = "merge:\(plan.id)"
    busy.insert(busyKey)
    defer { busy.remove(busyKey) }
    let draft = try await Analyzer.mergeSkills(plan, engine: .current)
    mergeDrafts[plan.id] = draft
    return draft
  }

  func merge(_ plan: SkillInstaller.MergePlan) async throws {
    guard let draft = mergeDrafts[plan.id] else {
      throw SkillInstaller.Failure.problem("There's no merged SKILL.md for \(plan.kept.name) yet.")
    }
    do {
      try SkillInstaller.merge(plan, markdown: draft)
    } catch {
      await refreshSkills()
      throw error
    }
    mergeDrafts[plan.id] = nil
    mergeKeep[SimilarPair.key(plan.kept.id, plan.merged.id)] = nil
    await refreshSkills()
    reveal(plan.kept.id)
  }

  @discardableResult
  func draft(_ id: Suggestion.ID) async throws -> String {
    guard let suggestion = suggestion(id) else { return "" }
    let busyKey = "draft:\(id)"
    busy.insert(busyKey)
    defer { busy.remove(busyKey) }
    let markdown = try await Analyzer.draftSkill(for: suggestion, engine: .current)
    updateDraft(id, markdown)
    return markdown
  }

  func updateDraft(_ id: Suggestion.ID, _ markdown: String) {
    guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
    suggestions[index].draft = markdown
    scheduleSave()
  }

  @discardableResult
  func save(_ id: Suggestion.ID, to target: SaveTarget) async throws -> URL {
    guard let index = suggestions.firstIndex(where: { $0.id == id }), let draft = suggestions[index].draft else {
      throw SkillInstaller.Failure.problem("Draft the skill before you save it.")
    }
    let folder = try SkillInstaller.save(markdown: draft, fallbackName: suggestions[index].name, to: target)
    suggestions[index].savedTo = folder.path
    saveState()
    await refreshSkills()
    return folder
  }

  func dismiss(_ id: Suggestion.ID) {
    guard let suggestion = suggestion(id) else { return }
    dismissed.append(suggestion.name)
    suggestions.removeAll { $0.id == id }
    saveState()
  }

  // MARK: - Persistence

  private struct SavedState: Codable {
    var suggestions: [Suggestion]
    var dismissed: [String]
    var explanations: [String: String]
    var analyzedIDs: [String]
    var lastAnalysis: Date?
    var dismissedPairs: [String]?
  }

  private func loadState() {
    guard let data = try? Data(contentsOf: stateFile),
          let state = try? JSONDecoder().decode(SavedState.self, from: data)
    else { return }
    suggestions = state.suggestions
    dismissed = state.dismissed
    explanations = state.explanations
    analyzedIDs = Set(state.analyzedIDs)
    lastAnalysis = state.lastAnalysis
    dismissedPairs = state.dismissedPairs ?? []
  }

  private func saveState() {
    saveTask?.cancel()
    saveTask = nil
    let state = SavedState(
      suggestions: suggestions,
      dismissed: dismissed,
      explanations: explanations,
      analyzedIDs: Array(analyzedIDs),
      lastAnalysis: lastAnalysis,
      dismissedPairs: dismissedPairs
    )
    guard let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: stateFile, options: .atomic)
  }

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      saveState()
    }
  }
}
