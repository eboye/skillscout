import Foundation
import Observation

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
  var analyzedIDs: Set<String> = []
  var lastAnalysis: Date?

  var isLoadingPrompts = false
  var isAnalyzing = false
  var busy: Set<String> = []
  var errorMessage: String?
  var searchRequests = 0

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

  func setTool(_ tool: Tool, enabled: Bool) {
    tools = Tool.allCases.filter { $0 == tool ? enabled : tools.contains($0) }
    UserDefaults.standard.set(tools.map(\.rawValue), forKey: "tools")
    applyTools()
  }

  func refreshSkills() async {
    skills = await Task.detached { SkillScanner.scan() }.value
    applyTools()
  }

  func refreshPrompts() async {
    isLoadingPrompts = true
    (allPrompts, uses) = await library.load(lookbackDays: UserDefaults.standard.integer(forKey: "lookbackDays"))
    applyTools()
    isLoadingPrompts = false
    await maybeAnalyzeAutomatically()
  }

  private func applyTools() {
    let enabled = Set(tools)
    prompts = allPrompts.filter { enabled.contains($0.tool) }
    usage = SkillUsage.tally(uses.filter { enabled.contains($0.tool) }, skills: skills)
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

  // MARK: - Actions

  func analyze() async {
    guard !isAnalyzing, !prompts.isEmpty else { return }
    isAnalyzing = true
    defer { isAnalyzing = false }

    do {
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
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func maybeAnalyzeAutomatically() async {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "autoAnalyze"),
          lastAnalysis != nil,
          newPromptCount >= defaults.integer(forKey: "autoThreshold"),
          lastAutoAttempt.map({ Date.now.timeIntervalSince($0) > 1800 }) ?? true
    else { return }
    lastAutoAttempt = .now
    await analyze()
  }

  func explain(_ skill: Skill) async {
    let key = skill.primary.contentHash
    let busyKey = "explain:\(key)"
    guard explanations[key] == nil, !busy.contains(busyKey),
          let text = try? String(contentsOf: skill.skillFile, encoding: .utf8)
    else { return }

    busy.insert(busyKey)
    defer { busy.remove(busyKey) }
    do {
      explanations[key] = try await Analyzer.explain(name: skill.name, skillText: text, engine: .current)
      saveState()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func add(_ skill: Skill, to tool: Tool) async {
    do {
      _ = try SkillInstaller.add(skill, to: tool)
      await refreshSkills()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func draft(_ id: Suggestion.ID) async {
    guard let suggestion = suggestion(id) else { return }
    let busyKey = "draft:\(id)"
    busy.insert(busyKey)
    defer { busy.remove(busyKey) }
    do {
      let markdown = try await Analyzer.draftSkill(for: suggestion, engine: .current)
      updateDraft(id, markdown)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func updateDraft(_ id: Suggestion.ID, _ markdown: String) {
    guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
    suggestions[index].draft = markdown
    scheduleSave()
  }

  func save(_ id: Suggestion.ID, to target: SaveTarget) async {
    guard let index = suggestions.firstIndex(where: { $0.id == id }), let draft = suggestions[index].draft else { return }
    do {
      let folder = try SkillInstaller.save(markdown: draft, fallbackName: suggestions[index].name, to: target)
      suggestions[index].savedTo = folder.path
      saveState()
      await refreshSkills()
    } catch {
      errorMessage = error.localizedDescription
    }
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
  }

  private func saveState() {
    saveTask?.cancel()
    saveTask = nil
    let state = SavedState(
      suggestions: suggestions,
      dismissed: dismissed,
      explanations: explanations,
      analyzedIDs: Array(analyzedIDs),
      lastAnalysis: lastAnalysis
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
