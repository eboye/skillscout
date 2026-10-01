import SwiftUI

struct ContentView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    NavigationSplitView {
      sidebarList
    } content: {
      if store.place == .suggestions {
        SuggestionList(suggestions: store.listedSuggestions, selection: Bindable(store).selectedSuggestion)
      } else if store.place == .similar {
        SimilarList(pairs: store.listedPairs, selection: Bindable(store).selectedPair)
      } else {
        SkillList(skills: store.listedSkills, selection: Bindable(store).selectedSkill)
      }
    } detail: {
      if store.place == .suggestions {
        if let suggestion = store.suggestion(store.selectedSuggestion) {
          SuggestionDetail(suggestion: suggestion)
        } else {
          ContentUnavailableView("Pick a suggestion", systemImage: "lightbulb")
        }
      } else if store.place == .similar {
        if let pair = store.listedPairs.first(where: { $0.id == store.selectedPair }) {
          SimilarDetail(pair: pair).id(pair.id)
        } else {
          ContentUnavailableView("Pick two similar skills", systemImage: "arrow.triangle.merge")
        }
      } else if let skill = store.skill(store.selectedSkill) {
        SkillDetail(skill: skill)
      } else {
        ContentUnavailableView("Pick a skill", systemImage: "square.stack.3d.up")
      }
    }
    .searchable(text: Bindable(store).search)
    .searchFocused($isSearchFocused)
    .onChange(of: store.searchRequests) { isSearchFocused = true }
    .task {
      store.showSettings = { openSettings() }
      store.showWindow = { openWindow(id: "main") }
    }
    .toolbar { toolbar }
    .modifier(Presentations(store: store))
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItemGroup {
      Button {
        store.editing = store.actionSkill
      } label: {
        Label("Edit", systemImage: "square.and.pencil")
      }
      .disabled(store.actionSkill == nil)
      .help("Edit the selected skill's SKILL.md")
      Button {
        store.renaming = store.actionSkill
      } label: {
        Label("Rename", systemImage: "character.cursor.ibeam")
      }
      .disabled(store.actionSkill == nil)
      .help("Rename the selected skill")
      Button {
        if let skill = store.actionSkill { store.removal = .uninstall(skill) }
      } label: {
        Label("Uninstall", systemImage: "trash")
      }
      .disabled(store.actionSkill == nil)
      .help("Uninstall the selected skill from every tool, by moving it to the Trash")
    }
    ToolbarItem {
      Picker("Sort", selection: Bindable(store).sort) {
        Text("Newest first").tag(SkillSort.newest)
        Text("Sort by name").tag(SkillSort.name)
        Text("Sort by use").tag(SkillSort.use)
      }
      .pickerStyle(.menu)
      .disabled(!(store.place?.listsSkills ?? true))
      .help("Sort skills by when you created them, by name, or by how often they're used")
    }
    ToolbarItem {
      Toggle(isOn: Bindable(store).showPluginSkills) {
        Label("Plugin and built-in skills", systemImage: "puzzlepiece.extension")
      }
      .help("Show plugin and built-in skills too")
    }
    ToolbarItem {
      Button {
        store.place = .suggestions
        store.perform { try await store.analyze() }
      } label: {
        Label("Find repeated tasks", systemImage: "sparkle.magnifyingglass")
      }
      .disabled(store.isAnalyzing || store.prompts.isEmpty)
      .help("Analyze your recent chats and suggest new skills")
    }
  }

  private var sidebarList: some View {
    List(selection: Bindable(store).place) {
      Section("Skills") {
        sidebarRow("All skills", symbol: "square.stack.3d.up", item: .allSkills)
        sidebarRow("Missing somewhere", symbol: "exclamationmark.triangle", item: .missing)
        sidebarRow("Unused", symbol: "moon.zzz", item: .unused)
      }
      Section("Available in") {
        ForEach(store.tools) { tool in
          sidebarRow(tool.name, symbol: tool.symbol, color: tool.color, item: .tool(tool))
        }
      }
      Section("Ideas") {
        sidebarRow("Suggestions", symbol: "lightbulb", item: .suggestions)
        sidebarRow("Similar skills", symbol: "arrow.triangle.merge", item: .similar)
      }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    .safeAreaInset(edge: .bottom) {
      StatusPanel()
    }
  }

  private func sidebarRow(_ title: String, symbol: String, color: Color? = nil, item: SidebarItem) -> some View {
    Label {
      Text(title)
    } icon: {
      Image(systemName: symbol).foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
    }
    .badge(store.count(in: item))
    .tag(item)
  }
}

struct StatusPanel: View {
  @Environment(AppStore.self) private var store
  @AppStorage("lookbackDays") private var lookbackDays = 60

  private var status: String {
    if store.isAnalyzing { return "Looking for repeated tasks…" }
    if store.isLoadingPrompts { return "Reading your chats…" }
    return "Watching your chats"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        if store.isAnalyzing || store.isLoadingPrompts {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
        }
        Text(status).font(.caption.weight(.medium))
      }
      Text("\(store.prompts.count) messages in the last \(lookbackDays) days")
        .font(.caption)
        .foregroundStyle(.secondary)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: 4), alignment: .leading, spacing: 4) {
        ForEach(store.tools) { tool in
          let count = store.prompts.count(where: { $0.tool == tool })
          if count > 0 {
            HStack(spacing: 3) {
              Image(systemName: tool.symbol).foregroundStyle(tool.color)
              Text("\(count)").lineLimit(1).minimumScaleFactor(0.8)
            }
            .help("\(count) messages from \(tool.name)")
          }
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      Group {
        if let last = store.lastAnalysis {
          Text("Analyzed \(last, format: .relative(presentation: .named)), \(store.newPromptCount) new since")
        } else {
          Text("Not analyzed yet")
        }
      }
      .font(.caption2)
      .foregroundStyle(.tertiary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The error alert, the uninstall confirmation and the sheets.
private struct Presentations: ViewModifier {
  @Bindable var store: AppStore

  func body(content: Content) -> some View {
    content
      .alert("Something went wrong", isPresented: Binding(
        get: { store.errorMessage != nil },
        set: { if !$0 { store.errorMessage = nil } }
      )) {
        Button("OK") {}
      } message: {
        Text(store.errorMessage ?? "")
      }
      .confirmationDialog(
        store.removal?.title ?? "",
        isPresented: Binding(
          get: { store.removal != nil },
          set: { if !$0 { store.removal = nil } }
        ),
        presenting: store.removal
      ) { removal in
        Button("Move to Trash", role: .destructive) {
          store.perform { try await store.remove(removal.copies) }
        }
      } message: { removal in
        Text(removal.message(tools: store.tools))
      }
      .sheet(item: $store.renaming) { RenameSheet(skill: $0) }
      .sheet(item: $store.editing) { EditSheet(skill: $0) }
  }
}
