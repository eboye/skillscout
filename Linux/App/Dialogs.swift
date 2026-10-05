import Adwaita
import Foundation

extension AIEngineKind: CustomStringConvertible {
  var description: String { name }
}

/// The days of chats to read, as Settings offers them.
struct Lookback: Identifiable, CustomStringConvertible {
  let id: Int
  var description: String { "\(id) days" }
  static let options = [30, 60, 90, 180].map(Lookback.init)
}

extension AnyView {
  /// The error alert, the uninstall confirmation, the rename and edit dialogs, and the app's
  /// preferences, about and shortcuts dialogs.
  func modifyDialogs(store: AppStore, model: WindowModel, app: AdwaitaApp) -> AnyView {
    let removal = store.removal
    return self
      .alertDialog(
        visible: Binding { store.errorMessage != nil } set: { if !$0 { store.errorMessage = nil } },
        heading: "Something went wrong",
        body: store.errorMessage ?? "",
        id: "error"
      )
      .response("OK", role: .close) {}
      .alertDialog(
        visible: Binding { model.notice != nil } set: { if !$0 { model.notice = nil } },
        heading: "Command line tool",
        body: model.notice ?? "",
        id: "notice"
      )
      .response("OK", role: .close) {}
      .alertDialog(
        visible: Binding { store.removal != nil } set: { if !$0 { store.removal = nil } },
        heading: removal?.title ?? "",
        body: removal?.message(tools: store.tools) ?? "",
        id: "removal"
      )
      .response("Cancel", role: .close) {}
      .response("Move to Trash", appearance: .destructive, role: .default) {
        guard let removal else { return }
        Task { await store.remove(removal.copies) }
      }
      .dialog(
        visible: Binding { store.renaming != nil } set: { if !$0 { store.renaming = nil } },
        title: "Rename \(store.renaming?.name ?? "")",
        id: "rename",
        width: 460
      ) {
        if let skill = store.renaming {
          RenameView(store: store, model: model, skill: skill)
        }
      }
      .dialog(
        visible: Binding { store.editing != nil } set: { visible in
          guard !visible else { return }
          if let edit = model.edit, model.editText != edit.original {
            model.confirmDiscard = true
          } else {
            store.editing = nil
          }
        },
        title: "Edit \(store.editing?.name ?? "")",
        id: "edit",
        width: 780,
        height: 680
      ) {
        if let skill = store.editing {
          EditView(store: store, model: model, skill: skill)
        }
      }
      .alertDialog(
        visible: Binding { model.confirmDiscard } set: { model.confirmDiscard = $0 },
        heading: "Discard your changes to \(store.editing?.name ?? "the skill")?",
        id: "discard"
      )
      .response("Keep Editing", role: .close) {}
      .response("Discard", appearance: .destructive, role: .default) {
        store.editing = nil
      }
      .preferences(store: store, model: model)
      .aboutDialog(
        visible: Binding { model.showAbout } set: { model.showAbout = $0 },
        app: "Skillscout",
        developer: "Flavio Copes",
        version: appVersion,
        icon: .custom(name: "com.flaviocopes.skillscout"),
        details: [
          .comment("Find the skills your coding agents load, see which agents can use each one, and count how often you use them."),
          .developers(["Flavio Copes https://flaviocopes.com"]),
          .licenseType(.mitX11),
        ],
        links: [
          .website(URL(string: "https://flaviocopes.com/skillscout/")),
          .issues(URL(string: "https://github.com/flaviocopes/skillscout/issues")),
        ]
      )
      .shortcutsDialog(visible: Binding { model.showShortcuts } set: { model.showShortcuts = $0 }, id: "shortcuts")
      .shortcutsSection("Skills") { section in
        section
          .shortcutsItem("Search", accelerator: "f".ctrl())
          .shortcutsItem("Uninstall the selected skill", accelerator: "Delete")
      }
      .shortcutsSection("General") { section in
        section
          .shortcutsItem("Preferences", accelerator: "comma".ctrl())
          .shortcutsItem("Keyboard shortcuts", accelerator: "question".ctrl())
          .shortcutsItem("Quit", accelerator: "q".ctrl())
      }
  }

  private func preferences(store: AppStore, model: WindowModel) -> AnyView {
    let defaults = UserDefaults.standard
    _ = model.settingsRevision
    func setting<Value>(_ key: String, _ read: @escaping () -> Value, _ write: @escaping (Value) -> Void) -> Binding<Value> {
      Binding(get: read, set: { value in
        write(value)
        model.settingsRevision += 1
      })
    }
    let engine = AIEngineKind(rawValue: defaults.string(forKey: "engine") ?? "") ?? .codex

    return preferencesDialog(visible: Binding { model.showPreferences } set: { model.showPreferences = $0 }, id: "preferences")
      .preferencesPage("General", icon: .custom(name: "preferences-system-symbolic")) { page in
        page
          .group("Tools", description: "Skillscout shows the skills these tools load, and reads their chats for usage and repeated tasks.") {
            Tool.allCases.map { tool -> AnyView in
              SwitchRow(tool.name, isOn: Binding { store.tools.contains(tool) } set: { store.setTool(tool, enabled: $0) })
                .subtitle(tool.isInstalled ? "" : "Not found on this computer")
            }
          }
          .group("AI", description: "Skillscout runs the CLI you're already logged in to. These runs aren't saved to your chat history.") {
            ComboRow(
              "Engine",
              selection: setting("engine", { engine.rawValue }, { defaults.set($0, forKey: "engine") }),
              values: AIEngineKind.allCases
            )
            EntryRow(
              "Model",
              text: setting(engine.modelKey, {
                defaults.string(forKey: engine.modelKey).flatMap { $0.isEmpty ? nil : $0 } ?? engine.defaultModel
              }, { defaults.set($0, forKey: engine.modelKey) })
            )
          }
          .group("Analysis", description: "Automatic analysis starts after your first manual one, and runs at most every 30 minutes.") {
            ComboRow(
              "Read messages from the last",
              selection: setting("lookbackDays", { defaults.integer(forKey: "lookbackDays") }, { days in
                guard days != defaults.integer(forKey: "lookbackDays") else { return }
                defaults.set(days, forKey: "lookbackDays")
                Task { await store.refreshPrompts() }
              }),
              values: Lookback.options
            )
            SwitchRow(
              "Analyze automatically",
              isOn: setting("autoAnalyze", { defaults.bool(forKey: "autoAnalyze") }, { defaults.set($0, forKey: "autoAnalyze") })
            )
            SpinRow(
              "After this many new messages",
              value: setting("autoThreshold", { defaults.integer(forKey: "autoThreshold") }, { defaults.set($0, forKey: "autoThreshold") }),
              min: 10,
              max: 500
            )
            .step(10)
            .insensitive(!defaults.bool(forKey: "autoAnalyze"))
          }
      }
  }
}

let appVersion = "1.4.0"

struct RenameView: View {
  let store: AppStore
  let model: WindowModel
  let skill: Skill

  private var name: String { model.renameText }

  private var problem: String? {
    name == skill.name ? nil : SkillInstaller.renameProblem(skill, to: name, among: store.skills)
  }

  private var note: String {
    let folders = skill.removableCopies.count(where: { !$0.isSymlink })
    let links = skill.removableCopies.count(where: \.isSymlink)
    var what: [String] = []
    if folders > 0 { what.append(folders == 1 ? "its folder" : "its \(folders) folders") }
    if links > 0 { what.append(links == 1 ? "the link to it" : "the \(links) links to it") }
    var sentences = ["Skillscout renames \(list(what)), and changes the name in SKILL.md."]

    let targets = skill.linkTargetsKept(skill.removableCopies)
    if !targets.isEmpty {
      sentences.append("\(list(targets.map(Paths.abbreviate))), where the links point, \(targets.count == 1 ? "keeps its" : "keep their") folder name.")
    }
    if let plugin = skill.copies.first(where: { $0.root.kind == .plugin }) {
      sentences.append("The copy from the \(plugin.sourceLabel) keeps the old name.")
    }
    sentences.append("Chats that used \(skill.name) still count.")
    return sentences.joined(separator: " ")
  }

  var view: Body {
    VStack(spacing: 14) {
      Entry("Name", text: Binding { model.renameText } set: { model.renameText = $0 })
        .activate { rename() }
      if let problem {
        paragraph(problem).error()
      }
      paragraph(note).dimLabel()
      HStack(spacing: 10) {
        Button("Cancel") { store.renaming = nil }
        Button("Rename") { rename() }
          .suggested()
          .insensitive(name == skill.name || problem != nil)
      }
      .halign(.end)
    }
    .padding(20)
    .topToolbar { HeaderBar.empty() }
  }

  private func rename() {
    guard name != skill.name, problem == nil else { return }
    store.renaming = nil
    Task { await store.rename(skill, to: name) }
  }
}

struct EditView: View {
  let store: AppStore
  let model: WindowModel
  let skill: Skill

  private var problem: String? { model.edit.flatMap { SkillInstaller.editProblem($0, text: model.editText) } }
  private var isChanged: Bool { model.edit.map { model.editText != $0.original } ?? false }

  private var note: String {
    guard let edit = model.edit else { return "" }
    var sentences = ["Skillscout saves it to \(list(edit.files.map(Paths.abbreviate)))."]
    if !edit.otherFiles.isEmpty {
      let one = edit.otherFiles.count == 1
      sentences.append("\(list(edit.otherFiles.map(Paths.abbreviate))) \(one ? "has" : "have") other text, so \(one ? "it stays as it is" : "they stay as they are").")
    }
    if let plugin = skill.copies.first(where: { $0.root.kind == .plugin }) {
      sentences.append("The copy from the \(plugin.sourceLabel) stays as it is.")
    }
    return sentences.joined(separator: " ")
  }

  var view: Body {
    VStack(spacing: 12) {
      plainTextEditor(Binding { model.editText } set: { model.editText = $0 }, editable: model.edit != nil, minHeight: 420)
        .vexpand()
      if let message = model.editFailure ?? problem {
        paragraph(message).error()
      } else if model.editChangedOnDisk {
        paragraph("SKILL.md changed since you opened it, maybe from an agent. Save anyway to replace those changes with yours.").warning()
      }
      paragraph(note).dimLabel()
      HStack(spacing: 10) {
        Button("Cancel") {
          if isChanged { model.confirmDiscard = true } else { store.editing = nil }
        }
        Button(model.editChangedOnDisk ? "Save Anyway" : "Save") { save() }
          .keyboardShortcut("s".ctrl())
          .suggested()
          .insensitive(!isChanged || problem != nil)
      }
      .halign(.end)
    }
    .padding(20)
    .topToolbar { HeaderBar.empty() }
  }

  private func save() {
    guard let edit = model.edit, isChanged, problem == nil else { return }
    Task {
      do {
        try await store.save(edit, text: model.editText, overwrite: model.editChangedOnDisk)
        store.editing = nil
      } catch SkillInstaller.Failure.changedOnDisk {
        model.editChangedOnDisk = true
      } catch {
        model.editFailure = error.localizedDescription
      }
    }
  }
}
