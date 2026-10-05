import Adwaita
import Foundation
import Observation

/// What the window shows: the SwiftUI views keep this in `@State` and `@AppStorage`. Here it lives
/// in one observable object, so every view reads it the same way it reads the store.
@MainActor
@Observable
final class WindowModel {
  var sidebar: SidebarItem = .allSkills {
    didSet { if sidebar.listsSkills != oldValue.listsSkills { showDetail = false } }
  }
  var selectedSkill = ""
  var selectedSuggestion = ""
  var selectedPair = ""
  var search = ""
  var source = SkillSource(rawValue: UserDefaults.standard.string(forKey: "skillSource") ?? "") ?? .yours {
    didSet { UserDefaults.standard.set(source.rawValue, forKey: "skillSource") }
  }
  var sort = SkillSort(rawValue: UserDefaults.standard.string(forKey: "skillSort") ?? "") ?? .newest {
    didSet { UserDefaults.standard.set(sort.rawValue, forKey: "skillSort") }
  }

  /// On a narrow window the panes stack, and these say which one is on top.
  var showList = false
  var showDetail = false

  var showPreferences = false
  var showAbout = false
  var showShortcuts = false
  /// Reading a Signal resets it, which would count as a change and render again, forever.
  @ObservationIgnored var searchFocus = Signal()

  var renameText = ""

  var edit: SkillInstaller.Edit?
  var editText = ""
  var editFailure: String?
  var editChangedOnDisk = false
  var confirmDiscard = false

  /// The name to keep for each similar pair, by `SimilarPair.id`.
  var keep: [String: Skill.ID] = [:]
  var confirmMerge = false

  var notice: String?
  /// Settings live in UserDefaults, which nothing observes, so a change bumps this.
  var settingsRevision = 0

  @ObservationIgnored private var renamingID: Skill.ID?
  @ObservationIgnored private var editingID: Skill.ID?
  @ObservationIgnored private var searchRequests = 0

  /// The SwiftUI views' `onChange` and `.task` work: follow a rename or merge to the new skill,
  /// leave a tool's section when you turn the tool off, and fill the rename and edit dialogs.
  func sync(with store: AppStore) {
    if let id = store.revealRequest {
      if !sidebar.listsSkills { sidebar = .allSkills }
      selectedSkill = id
      showList = true
      showDetail = true
      store.revealRequest = nil
    }
    if case .tool(let tool) = sidebar, !store.tools.contains(tool) { sidebar = .allSkills }
    if store.searchRequests != searchRequests {
      searchRequests = store.searchRequests
      searchFocus.signal()
    }

    if store.renaming?.id != renamingID {
      renamingID = store.renaming?.id
      renameText = store.renaming?.name ?? ""
    }
    if store.editing?.id != editingID {
      editingID = store.editing?.id
      edit = nil
      editText = ""
      editFailure = nil
      editChangedOnDisk = false
      if let skill = store.editing {
        do {
          let edit = try SkillInstaller.edit(skill)
          editText = edit.original
          self.edit = edit
        } catch {
          editFailure = error.localizedDescription
        }
      }
    }
  }
}

/// Re-renders the window when the store or the window model changes, the way SwiftUI follows an
/// `@Observable`. Adwaita for Swift only re-renders on its own `@State`, so this watches every
/// property the views read, and asks the app's state manager for one update per batch of changes.
@MainActor
final class Renderer {
  private let store: AppStore
  private let model: WindowModel
  private var stateManager: StateManager?
  private var scheduled = false

  init(store: AppStore, model: WindowModel) {
    self.store = store
    self.model = model
    track()
  }

  /// The views hand over the state manager the first time they render.
  func attach(_ stateManager: StateManager) {
    guard self.stateManager == nil else { return }
    self.stateManager = stateManager
  }

  private func track() {
    withObservationTracking {
      read(store)
      read(model)
    } onChange: { [weak self] in
      Task { @MainActor in self?.changed() }
    }
  }

  private func changed() {
    model.sync(with: store)
    track()
    guard !scheduled else { return }
    scheduled = true
    Task { @MainActor in
      scheduled = false
      stateManager?.updateViews(force: true)
    }
  }

  private func read(_ store: AppStore) {
    _ = (store.skills, store.prompts, store.usage, store.tools, store.suggestions, store.explanations)
    _ = (store.dismissed, store.similar, store.dismissedPairs, store.mergeDrafts, store.analyzedIDs, store.lastAnalysis)
    _ = (store.isLoadingPrompts, store.isAnalyzing, store.busy, store.errorMessage, store.searchRequests)
    _ = (store.removal, store.renaming, store.editing, store.revealRequest)
  }

  private func read(_ model: WindowModel) {
    _ = (model.sidebar, model.selectedSkill, model.selectedSuggestion, model.selectedPair, model.search)
    _ = (model.source, model.sort, model.showList, model.showDetail, model.showPreferences, model.showAbout)
    _ = (model.showShortcuts, model.renameText, model.edit, model.editText, model.editFailure, model.editChangedOnDisk)
    _ = (model.confirmDiscard, model.keep, model.confirmMerge, model.notice, model.settingsRevision)
  }
}
