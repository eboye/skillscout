import Adwaita
import CAdw
import Foundation

/// The GNOME version of ContentView.swift: the sidebar, the list and the detail pane, with the
/// header bars, dialogs and alerts.
struct ContentView: View {
  let store: AppStore
  let model: WindowModel
  let app: AdwaitaApp
  @State private var wide = true
  @State private var roomy = true

  // MARK: - What's listed

  private var enabledSkills: [Skill] {
    let tools = Set(store.tools)
    return store.skills.filter { !$0.availableIn.isDisjoint(with: tools) }
  }

  private var librarySkills: [Skill] { enabledSkills.filter(model.source.includes) }

  private func isMissing(_ skill: Skill) -> Bool {
    skill.isPersonal && !skill.missing(from: store.tools).isEmpty
  }

  private var listedSkills: [Skill] {
    var skills: [Skill]
    switch model.sidebar {
    case .missing: skills = librarySkills.filter(isMissing)
    case .unused: skills = librarySkills.filter { store.usage[$0.id] == nil }
    case .tool(let tool): skills = librarySkills.filter { $0.availableIn.contains(tool) }
    default: skills = librarySkills
    }
    if !model.search.isEmpty {
      skills = skills.filter {
        $0.name.localizedCaseInsensitiveContains(model.search) || $0.description.localizedCaseInsensitiveContains(model.search)
      }
    }
    return skills.sorted { model.sort.inOrder($0, $1) { store.usage[$0.id] } }
  }

  private var listedPairs: [SimilarPair] {
    let listed = Set(enabledSkills.map(\.id))
    let search = model.search
    return store.similar.filter { pair in
      listed.contains(pair.first) && listed.contains(pair.second)
        && (search.isEmpty || pair.first.localizedCaseInsensitiveContains(search) || pair.second.localizedCaseInsensitiveContains(search))
    }
  }

  private var listedSuggestions: [Suggestion] {
    guard !model.search.isEmpty else { return store.suggestions }
    return store.suggestions.filter {
      $0.title.localizedCaseInsensitiveContains(model.search) || $0.summary.localizedCaseInsensitiveContains(model.search)
    }
  }

  /// The selected skill, when it's yours to rename or uninstall.
  private var actionSkill: Skill? {
    guard model.sidebar.listsSkills, let skill = store.skill(model.selectedSkill), skill.isPersonal else { return nil }
    return skill
  }

  /// Merging keeps the skill you use more, or the one more tools load.
  private func suggestedKeep(_ pair: SimilarPair) -> Skill.ID {
    func weight(_ id: Skill.ID) -> (Int, Int) { (store.usage[id]?.chats ?? 0, store.skill(id)?.availableIn.count ?? 0) }
    return weight(pair.second) > weight(pair.first) ? pair.second : pair.first
  }

  // MARK: - Layout

  var view: Body {
    NavigationSplitView {
      SidebarPane(store: store, model: model, app: app, skills: librarySkills, missing: librarySkills.count(where: isMissing), pairs: listedPairs.count)
        .navigationTitle("Skill Cabinet")
    } content: {
      NavigationSplitView {
        listPane
          .navigationTitle(listTitle)
      } content: {
        detailPane
          .navigationTitle("Details")
      }
      .collapsed(!wide)
      .showContent(Binding { model.showDetail } set: { model.showDetail = $0 })
      .inspect { storage, _ in sidebarWidth(storage, min: 320, max: 420, fraction: 0.42) }
      .navigationTitle(listTitle)
    }
    .collapsed(!roomy)
    .showContent(Binding { model.showList } set: { model.showList = $0 })
    .inspect { storage, _ in sidebarWidth(storage, min: 210, max: 250, fraction: 0.2) }
    .breakpoint(minWidth: 900, matches: $wide)
    .breakpoint(minWidth: 560, matches: $roomy)
    .css { appCSS }
    .modifyDialogs(store: store, model: model, app: app)
  }

  /// The SwiftUI columns' `navigationSplitViewColumnWidth`.
  private func sidebarWidth(_ storage: ViewStorage, min: Double, max: Double, fraction: Double) {
    adw_navigation_split_view_set_min_sidebar_width(storage.opaquePointer, min)
    adw_navigation_split_view_set_max_sidebar_width(storage.opaquePointer, max)
    adw_navigation_split_view_set_sidebar_width_fraction(storage.opaquePointer, fraction)
  }

  private var listTitle: String {
    switch model.sidebar {
    case .allSkills: "All skills"
    case .missing: "Missing somewhere"
    case .unused: "Unused"
    case .tool(let tool): tool.name
    case .suggestions: "Suggestions"
    case .similar: "Similar skills"
    }
  }

  private func sourceButton(_ source: SkillSource) -> AnyView {
    MenuButton((model.source == source ? "✓  " : "    ") + source.description) { model.source = source }
  }

  private func sortButton(_ sort: SkillSort) -> AnyView {
    MenuButton((model.sort == sort ? "✓  " : "    ") + sort.description) { model.sort = sort }
  }

  @ViewBuilder private var listPane: Body {
    VStack {
      if model.sidebar == .suggestions {
        SuggestionList(store: store, model: model, suggestions: listedSuggestions)
      } else if model.sidebar == .similar {
        SimilarList(model: model, pairs: listedPairs)
      } else {
        SkillList(store: store, model: model, skills: listedSkills)
      }
    }
    .topToolbar {
      HeaderBar {
        if model.sidebar.listsSkills {
          Menu(icon: .custom(name: "view-more-symbolic")) {
            MenuSection {
              sourceButton(.yours)
              sourceButton(.plugin)
              sourceButton(.builtIn)
            }
            MenuSection {
              sourceButton(.all)
            }
            MenuSection {
              sortButton(.newest)
              sortButton(.name)
              sortButton(.use)
            }
          }
          .tooltip("Show your own skills, plugin or built-in ones, and pick the order")
        }
      } end: {
        Button(icon: .custom(name: "media-playlist-repeat-symbolic")) {
          model.sidebar = .suggestions
          model.showList = true
          Task { await store.analyze() }
        }
        .tooltip("Find repeated tasks: analyze your recent chats and suggest new skills")
        .insensitive(store.isAnalyzing || store.prompts.isEmpty)
      }
      .headerBarTitle {
        SearchEntry()
          .text(Binding { model.search } set: { model.search = $0 })
          .placeholderText("Search")
          .focus(Binding { model.searchFocus } set: { model.searchFocus = $0 })
          .hexpand()
      }
    }
  }

  @ViewBuilder private var detailPane: Body {
    VStack {
      if model.sidebar == .suggestions {
        if let suggestion = store.suggestion(UUID(uuidString: model.selectedSuggestion)) {
          SuggestionDetail(store: store, suggestion: suggestion)
        } else {
          StatusPage("Pick a suggestion", icon: .custom(name: "dialog-information-symbolic"))
        }
      } else if model.sidebar == .similar {
        if let pair = listedPairs.first(where: { $0.id == model.selectedPair }) {
          SimilarDetail(store: store, model: model, pair: pair, keep: model.keep[pair.id] ?? suggestedKeep(pair))
        } else {
          StatusPage("Pick two similar skills", icon: .custom(name: "view-dual-symbolic"))
        }
      } else if let skill = store.skill(model.selectedSkill) {
        SkillDetail(store: store, skill: skill)
      } else {
        StatusPage("Pick a skill", icon: .custom(name: "view-list-bullet-symbolic"))
      }
    }
    .topToolbar {
      HeaderBar {
      } end: {
        // The end of a header bar fills from the right, so these show as Edit, Rename, Uninstall,
        // like the Mac toolbar. Edit and Rename use the app's own icons, after the Mac's SF Symbols,
        // since icon themes like Papirus draw the stock edit icons as the same pencil.
        Button(icon: .custom(name: "user-trash-symbolic")) {
          if let skill = actionSkill { store.removal = .uninstall(skill) }
        }
        .tooltip("Uninstall the selected skill from every tool, by moving it to the Trash")
        .insensitive(actionSkill == nil)
        Button(icon: .custom(name: "com.flaviocopes.skillscout-rename-symbolic")) {
          store.renaming = actionSkill
        }
        .tooltip("Rename the selected skill")
        .insensitive(actionSkill == nil)
        Button(icon: .custom(name: "com.flaviocopes.skillscout-edit-symbolic")) {
          store.editing = actionSkill
        }
        .tooltip("Edit the selected skill's SKILL.md")
        .insensitive(actionSkill == nil)
      }
      .headerBarTitle { Text("") }
    }
  }
}

/// The sections of the sidebar, and the status panel under them.
struct SidebarPane: View {
  let store: AppStore
  let model: WindowModel
  let app: AdwaitaApp
  let skills: [Skill]
  let missing: Int
  let pairs: Int

  struct Entry: Identifiable {
    let id: String
    let title: String
    let count: Int
    let item: SidebarItem
  }

  private var skillEntries: [Entry] {
    [
      Entry(id: "all", title: "All skills", count: skills.count, item: .allSkills),
      Entry(id: "missing", title: "Missing somewhere", count: missing, item: .missing),
      Entry(id: "unused", title: "Unused", count: skills.count(where: { store.usage[$0.id] == nil }), item: .unused),
    ]
  }

  private var toolEntries: [Entry] {
    store.tools.map { tool in
      Entry(id: "tool:\(tool.rawValue)", title: tool.name, count: skills.count(where: { $0.availableIn.contains(tool) }), item: .tool(tool))
    }
  }

  private var ideaEntries: [Entry] {
    [
      Entry(id: "suggestions", title: "Suggestions", count: store.suggestions.count, item: .suggestions),
      Entry(id: "similar", title: "Similar skills", count: pairs, item: .similar),
    ]
  }

  private var selectedID: String {
    (skillEntries + toolEntries + ideaEntries).first { $0.item == model.sidebar }?.id ?? ""
  }

  var view: Body {
    ScrollView {
      VStack(spacing: 6) {
        section("Skills", skillEntries)
        section("Available in", toolEntries)
        section("Ideas", ideaEntries)
      }
      .padding(6, .vertical)
    }
    .hscrollbarPolicy(.never)
    .vexpand()
    .bottomToolbar {
      StatusPanel(store: store)
    }
    .topToolbar {
      HeaderBar.end {
        Menu(icon: .default(icon: .openMenu)) {
          MenuSection {
            MenuButton("Preferences") { model.showPreferences = true }
              .keyboardShortcut("comma".ctrl())
            MenuButton("Install Command Line Tool") {
              model.notice = CommandLineTool.install()
            }
            MenuButton("Keyboard Shortcuts") { model.showShortcuts = true }
              .keyboardShortcut("question".ctrl())
            MenuButton("About Skill Cabinet") { model.showAbout = true }
          }
          MenuSection {
            MenuButton("Quit", window: false) { app.quit() }
              .keyboardShortcut("q".ctrl())
          }
        }
        .primary()
        .tooltip("Main Menu")
      }
      .headerBarTitle { WindowTitle(subtitle: "", title: "Skill Cabinet") }
    }
    .navigationTitle("Skill Cabinet")
  }

  private func section(_ title: String, _ entries: [Entry]) -> AnyView {
    VStack {
      Text(title)
        .captionHeading()
        .dimLabel()
        .halign(.start)
        .padding(12, .horizontal)
        .padding(6, .top)
      List(entries, selection: Binding { selectedID } set: { id in
        guard let entry = entries.first(where: { $0.id == id }), entry.item != model.sidebar else { return }
        model.sidebar = entry.item
        model.showList = true
      }) { entry in
        HStack(spacing: 8) {
          Text(entry.title)
            .ellipsize()
            .halign(.start)
            .hexpand()
          Text(entry.count.formatted())
            .numeric()
            .dimLabel()
        }
        .padding(8, .vertical)
        .padding(6, .horizontal)
      }
      .sidebarStyle()
      .inspect { storage, _ in
        // Each section is its own list, so the ones without the selection let go of theirs.
        if !entries.contains(where: { $0.id == selectedID }) {
          gtk_list_box_unselect_all(storage.opaquePointer)
        }
      }
    }
  }
}

struct StatusPanel: View {
  let store: AppStore

  private var status: String {
    if store.isAnalyzing { return "Looking for repeated tasks…" }
    if store.isLoadingPrompts { return "Reading your chats…" }
    return "Watching your chats"
  }

  private var perTool: String {
    store.tools.compactMap { tool in
      let count = store.prompts.count(where: { $0.tool == tool })
      return count > 0 ? "\(tool.shortName) \(count.formatted())" : nil
    }
    .joined(separator: " · ")
  }

  var view: Body {
    VStack(spacing: 4) {
      HStack(spacing: 6) {
        if store.isAnalyzing || store.isLoadingPrompts {
          Spinner()
        } else {
          Text("●").success()
        }
        Text(status).captionHeading()
      }
      .halign(.start)
      paragraph("\(plural(store.prompts.count, "message")) in the last \(UserDefaults.standard.integer(forKey: "lookbackDays")) days")
        .caption()
        .dimLabel()
      if !perTool.isEmpty {
        paragraph(perTool).caption().dimLabel()
      }
      if let last = store.lastAnalysis {
        paragraph("Analyzed \(relative(last)), \(store.newPromptCount) new since").caption().dimLabel()
      } else {
        paragraph("Not analyzed yet").caption().dimLabel()
      }
    }
    .style("status-panel")
  }
}
