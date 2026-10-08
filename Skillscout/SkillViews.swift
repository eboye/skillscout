import SwiftUI

struct SkillList: View {
  @Environment(AppStore.self) private var store
  let skills: [Skill]
  @Binding var selection: Skill.ID?

  var body: some View {
    List(skills, selection: $selection) { skill in
      SkillRow(skill: skill)
    }
    .contextMenu(forSelectionType: Skill.ID.self) { ids in
      if let skill = store.skill(ids.first), skill.isPersonal {
        Button("Edit SKILL.md…") { store.editing = skill }
        Button("Rename…") { store.renaming = skill }
        Button("Uninstall", role: .destructive) { store.removal = .uninstall(skill) }
      }
    }
    .onDeleteCommand {
      if let skill = store.skill(selection), skill.isPersonal { store.removal = .uninstall(skill) }
    }
    .overlay {
      if skills.isEmpty {
        ContentUnavailableView("No skills here", systemImage: "square.stack.3d.up.slash")
      }
    }
    .navigationSplitViewColumnWidth(min: 320, ideal: 400)
  }
}

struct SkillRow: View {
  @Environment(AppStore.self) private var store
  let skill: Skill

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(skill.name)
          .font(.body.weight(.semibold))
          .lineLimit(1)
        Spacer()
        if let usage = store.usage[skill.id] {
          Text("^[\(usage.chats) chat](inflect: true)")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        AvailabilityBadges(available: skill.availableIn, tools: store.tools)
      }
      if !skill.description.isEmpty {
        Text(skill.description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 4)
  }
}

struct SkillDetail: View {
  @Environment(AppStore.self) private var store
  let skill: Skill
  @State private var content = ""
  @AppStorage("lookbackDays") private var lookbackDays = 60

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 6) {
          Text(skill.name)
            .font(.largeTitle.bold())
          if !skill.description.isEmpty {
            Text(skill.description)
              .font(.title3)
              .foregroundStyle(.secondary)
          }
        }
        .textSelection(.enabled)

        DetailSection("Available in") {
          ForEach(store.tools) { tool in
            availabilityRow(tool)
          }
        }
        DetailSection("Usage") {
          usageSummary
        }
        DetailSection("What it does") {
          explanation
        }
        DetailSection("Where it lives") {
          locations
        }
        DetailSection("SKILL.md") {
          file
        }
      }
      .padding(28)
      .frame(maxWidth: 820, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task(id: skill.primary) {
      content = (try? String(contentsOf: skill.skillFile, encoding: .utf8)) ?? ""
    }
  }

  private func availabilityRow(_ tool: Tool) -> some View {
    HStack(spacing: 10) {
      ToolBadge(tool: tool, active: skill.availableIn.contains(tool))
        .frame(width: 76, alignment: .leading)

      if let provider = skill.provider(for: tool) {
        Text(provider.root.kind == .plugin ? "From the \(provider.sourceLabel)" : "Loaded from \(Paths.abbreviate(provider.root.url))")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else if skill.isBuiltInOnly {
        Text("Built into \(skill.primary.root.owner?.name ?? "another tool"), so it stays there")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        Button(skill.isPluginOnly ? "Copy to \(tool.name)" : "Add to \(tool.name)") {
          Task { await store.add(skill, to: tool) }
        }
        Text(skill.isPluginOnly ? "copies the folder into \(Paths.abbreviate(tool.skillsFolder))" : "links it into \(Paths.abbreviate(tool.skillsFolder))")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private var usageSummary: some View {
    if let usage = store.usage[skill.id] {
      VStack(alignment: .leading, spacing: 10) {
        Text("Used in ^[\(usage.chats) chat](inflect: true) in the last \(lookbackDays) days, most recently \(usage.lastUsed, format: .relative(presentation: .named)).")
        HStack(spacing: 14) {
          ForEach(Tool.allCases.filter { usage.byTool[$0] != nil }) { tool in
            HStack(spacing: 5) {
              ToolBadge(tool: tool)
              Text("\(usage.byTool[tool] ?? 0)")
                .font(.callout)
                .monospacedDigit()
            }
          }
        }
        if !usage.topProjects.isEmpty {
          Text("Mostly in \(usage.topProjects.formatted(.list(type: .and)))")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    } else {
      Text("Not used in the last \(lookbackDays) days.")
        .foregroundStyle(.secondary)
    }
    Text("A use is a chat where the agent read this skill, or where you attached it yourself.")
      .font(.caption)
      .foregroundStyle(.tertiary)
  }

  @ViewBuilder
  private var explanation: some View {
    let key = skill.primary.contentHash
    if let text = store.explanations[key] {
      Text(text)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    } else if store.busy.contains("explain:\(key)") {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading the skill…").foregroundStyle(.secondary)
      }
    } else {
      Button {
        Task { await store.explain(skill) }
      } label: {
        Label("Explain with AI", systemImage: "sparkles")
      }
    }
  }

  private var locations: some View {
    VStack(alignment: .leading, spacing: 12) {
      let created = skill.created(usage: store.usage[skill.id])
      if created != .distantPast {
        Text("Created \(created, format: .dateTime.day().month(.wide).year())")
          .foregroundStyle(.secondary)
      }
      ForEach(skill.copies) { copy in
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(copy.sourceLabel)
              .font(.callout.weight(.medium))
            Text(copy.isSymlink ? "\(Paths.abbreviate(copy.folder)) → \(Paths.abbreviate(copy.resolved))" : Paths.abbreviate(copy.folder))
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          Spacer()
          Button("Show in Finder") { Finder.reveal(copy.folder) }
            .buttonStyle(.link)
          if skill.removableCopies.count > 1, skill.removableCopies.contains(copy) {
            Button("Remove") { store.removal = .copy(copy, of: skill) }
              .buttonStyle(.link)
          }
        }
      }
      if skill.copiesDiffer {
        Label("These copies have different content, so editing one won't update the others.", systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.orange)
      }
      if skill.isPersonal {
        HStack(spacing: 10) {
          Button("Rename…") { store.renaming = skill }
          Button("Uninstall this skill", role: .destructive) { store.removal = .uninstall(skill) }
        }
      } else if let plugin = skill.copies.first(where: { $0.root.kind == .plugin }) {
        Text("It comes from the \(plugin.sourceLabel), so uninstall the plugin to remove it.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var file: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 14) {
        if skill.isPersonal {
          Button("Edit") { store.editing = skill }
        }
        Button("Open in editor") { Finder.open(skill.skillFile) }
      }
      .buttonStyle(.link)
      Text(content)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
  }
}

/// Copies of a skill on their way to the Trash, with the words that confirm it.
struct Removal {
  let skill: Skill
  let copies: [SkillCopy]

  static func uninstall(_ skill: Skill) -> Removal {
    Removal(skill: skill, copies: skill.removableCopies)
  }

  static func copy(_ copy: SkillCopy, of skill: Skill) -> Removal {
    Removal(skill: skill, copies: skill.copiesGoing(with: copy))
  }

  var title: String {
    copies.count == skill.removableCopies.count
      ? "Uninstall \(skill.name)?"
      : "Remove \(skill.name) from \(Paths.abbreviate(copies[0].root.url))?"
  }

  func message(tools: [Tool]) -> String {
    let folders = copies.map { Paths.abbreviate($0.root.url) }
    var sentences = ["Skill Cabinet moves it to the Trash from \(folders.formatted(.list(type: .and)))."]

    let losing = tools.filter(skill.toolsLosing(copies).contains)
    if losing.isEmpty {
      sentences.append("Your agents still load it from another folder.")
    } else if losing == tools.filter(skill.availableIn.contains) {
      sentences.append("None of your agents will load it anymore.")
    } else {
      sentences.append("\(losing.map(\.name).formatted(.list(type: .and))) will stop loading it.")
    }

    let targets = skill.linkTargetsKept(copies)
    if !targets.isEmpty {
      let links = copies.count(where: { $0.isSymlink && targets.contains($0.resolved) })
      sentences.append(
        "\(links == 1 ? "The link points" : "The links point") to \(targets.map(Paths.abbreviate).formatted(.list(type: .and))), "
          + "\(targets.count == 1 ? "which stays where it is" : "which stay where they are")."
      )
    }
    return sentences.joined(separator: " ")
  }
}

struct RenameSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let skill: Skill
  @State private var name: String

  init(skill: Skill) {
    self.skill = skill
    _name = State(initialValue: skill.name)
  }

  private var problem: String? {
    name == skill.name ? nil : SkillInstaller.renameProblem(skill, to: name, among: store.skills)
  }

  private var note: String {
    let folders = skill.removableCopies.count(where: { !$0.isSymlink })
    let links = skill.removableCopies.count(where: \.isSymlink)
    var what: [String] = []
    if folders > 0 { what.append(folders == 1 ? "its folder" : "its \(folders) folders") }
    if links > 0 { what.append(links == 1 ? "the link to it" : "the \(links) links to it") }
    var sentences = ["Skill Cabinet renames \(what.formatted(.list(type: .and))), and changes the name in SKILL.md."]

    let targets = skill.linkTargetsKept(skill.removableCopies)
    if !targets.isEmpty {
      sentences.append("\(targets.map(Paths.abbreviate).formatted(.list(type: .and))), where the links point, \(targets.count == 1 ? "keeps its" : "keep their") folder name.")
    }
    if let plugin = skill.copies.first(where: { $0.root.kind == .plugin }) {
      sentences.append("The copy from the \(plugin.sourceLabel) keeps the old name.")
    }
    sentences.append("Chats that used \(skill.name) still count.")
    return sentences.joined(separator: " ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename \(skill.name)")
        .font(.headline)
      TextField("Name", text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit(rename)
      if let problem {
        Text(problem)
          .font(.callout)
          .foregroundStyle(.red)
      }
      Text(note)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Rename", action: rename)
          .keyboardShortcut(.defaultAction)
          .disabled(name == skill.name || problem != nil)
      }
    }
    .padding(20)
    .frame(width: 440)
  }

  private func rename() {
    guard name != skill.name, problem == nil else { return }
    dismiss()
    Task { await store.rename(skill, to: name) }
  }
}

struct EditSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let skill: Skill
  @State private var edit: SkillInstaller.Edit?
  @State private var text = ""
  @State private var failure: String?
  @State private var changedOnDisk = false
  @State private var discarding = false

  private var problem: String? { edit.flatMap { SkillInstaller.editProblem($0, text: text) } }
  private var isChanged: Bool { edit.map { text != $0.original } ?? false }

  private var note: String {
    guard let edit else { return "" }
    var sentences = ["Skill Cabinet saves it to \(edit.files.map(Paths.abbreviate).formatted(.list(type: .and)))."]
    if !edit.otherFiles.isEmpty {
      let one = edit.otherFiles.count == 1
      sentences.append("\(edit.otherFiles.map(Paths.abbreviate).formatted(.list(type: .and))) \(one ? "has" : "have") other text, so \(one ? "it stays as it is" : "they stay as they are").")
    }
    if let plugin = skill.copies.first(where: { $0.root.kind == .plugin }) {
      sentences.append("The copy from the \(plugin.sourceLabel) stays as it is.")
    }
    return sentences.joined(separator: " ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Edit \(skill.name)")
        .font(.headline)
      PlainTextEditor(text: $text)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .disabled(edit == nil)
      if let message = failure ?? problem {
        Text(message)
          .font(.callout)
          .foregroundStyle(.red)
      } else if changedOnDisk {
        Text("SKILL.md changed since you opened it, maybe from an agent. Save anyway to replace those changes with yours.")
          .font(.callout)
          .foregroundStyle(.orange)
      }
      Text(note)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          if isChanged { discarding = true } else { dismiss() }
        }
        .keyboardShortcut(.cancelAction)
        Button(changedOnDisk ? "Save anyway" : "Save", action: save)
          .keyboardShortcut("s")
          .buttonStyle(.borderedProminent)
          .disabled(!isChanged || problem != nil)
      }
    }
    .padding(20)
    .frame(minWidth: 640, idealWidth: 760, minHeight: 480, idealHeight: 640)
    .task {
      do {
        let edit = try SkillInstaller.edit(skill)
        text = edit.original
        self.edit = edit
      } catch {
        failure = error.localizedDescription
      }
    }
    .confirmationDialog("Discard your changes to \(skill.name)?", isPresented: $discarding) {
      Button("Discard", role: .destructive) { dismiss() }
    }
  }

  private func save() {
    guard let edit, isChanged, problem == nil else { return }
    Task {
      do {
        try await store.save(edit, text: text, overwrite: changedOnDisk)
        dismiss()
      } catch SkillInstaller.Failure.changedOnDisk {
        changedOnDisk = true
      } catch {
        failure = error.localizedDescription
      }
    }
  }
}
