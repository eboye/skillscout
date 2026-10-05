import Adwaita
import Foundation

struct SkillList: View {
  let store: AppStore
  let model: WindowModel
  let skills: [Skill]

  var view: Body {
    if skills.isEmpty {
      StatusPage("No skills here", icon: .custom(name: "view-list-bullet-symbolic"))
        .vexpand()
    } else {
      ScrollView {
        List(skills, selection: Binding { model.selectedSkill } set: { id in
          model.selectedSkill = id
          model.showDetail = true
        }) { skill in
          SkillRow(store: store, skill: skill)
        }
        .style("navigation-sidebar")
      }
      .hscrollbarPolicy(.never)
      .vexpand()
    }
  }
}

struct SkillRow: View {
  let store: AppStore
  let skill: Skill

  var view: Body {
    VStack(spacing: 4) {
      HStack(spacing: 8) {
        Text(skill.name)
          .ellipsize()
          .heading()
          .halign(.start)
          .hexpand()
        if let usage = store.usage[skill.id] {
          Text(plural(usage.chats, "chat"))
            .caption()
            .numeric()
            .dimLabel()
        }
        AvailabilityBadges(available: skill.availableIn, tools: store.tools)
      }
      if !skill.description.isEmpty {
        Text(skill.description)
          .wrap()
          .lines(2)
          .ellipsize()
          .xalign(0)
          .dimLabel()
      }
    }
    .style("skill-row")
  }
}

struct SkillDetail: View {
  let store: AppStore
  let skill: Skill

  private var lookbackDays: Int { UserDefaults.standard.integer(forKey: "lookbackDays") }

  var view: Body {
    ScrollView {
      VStack(spacing: 28) {
        VStack(spacing: 6) {
          paragraph(skill.name, selectable: true).title1()
          if !skill.description.isEmpty {
            paragraph(skill.description, selectable: true).title4().dimLabel()
          }
        }
        DetailSection("Available in") {
          ForEach(store.tools) { tool in availabilityRow(tool) }
        }
        DetailSection("Usage") { usageSummary }
        DetailSection("What it does") { explanation }
        DetailSection("Where it lives") { locations }
        DetailSection("SKILL.md") { file }
      }
      .style("detail")
      .frame(maxWidth: 820)
    }
    .hscrollbarPolicy(.never)
    .vexpand()
  }

  private func availabilityRow(_ tool: Tool) -> AnyView {
    HStack(spacing: 10) {
      ToolBadge(tool: tool, active: skill.availableIn.contains(tool))
        .frame(minWidth: 76)
        .halign(.start)
      if let provider = skill.provider(for: tool) {
        paragraph(provider.root.kind == .plugin ? "From the \(provider.sourceLabel)" : "Loaded from \(Paths.abbreviate(provider.root.url))")
          .dimLabel()
      } else if skill.isBuiltInOnly {
        paragraph("Built into \(skill.primary.root.owner?.name ?? "another tool"), so it stays there").dimLabel()
      } else {
        Button(skill.isPluginOnly ? "Copy to \(tool.name)" : "Add to \(tool.name)") {
          Task { await store.add(skill, to: tool) }
        }
        paragraph(skill.isPluginOnly ? "copies the folder into \(Paths.abbreviate(tool.skillsFolder))" : "links it into \(Paths.abbreviate(tool.skillsFolder))")
          .caption()
          .dimLabel()
      }
    }
    .halign(.start)
  }

  @ViewBuilder private var usageSummary: Body {
    if let usage = store.usage[skill.id] {
      paragraph("Used in \(plural(usage.chats, "chat")) in the last \(lookbackDays) days, most recently \(relative(usage.lastUsed)).")
      ForEach(Tool.allCases.filter { usage.byTool[$0] != nil }) { tool in
        HStack(spacing: 5) {
          ToolBadge(tool: tool)
          Text("\(usage.byTool[tool] ?? 0)").numeric()
        }
      }
      .orientation(.horizontal)
      .style("badge-row")
      .halign(.start)
      if !usage.topProjects.isEmpty {
        paragraph("Mostly in \(list(usage.topProjects))").dimLabel()
      }
    } else {
      paragraph("Not used in the last \(lookbackDays) days.").dimLabel()
    }
    paragraph("A use is a chat where the agent read this skill, or where you attached it yourself.").caption().dimLabel()
  }

  @ViewBuilder private var explanation: Body {
    let key = skill.primary.contentHash
    if let text = store.explanations[key] {
      paragraph(text, selectable: true)
    } else if store.busy.contains("explain:\(key)") {
      HStack(spacing: 8) {
        Spinner()
        Text("Reading the skill…").dimLabel()
      }
      .halign(.start)
    } else {
      Button("Explain with AI") { Task { await store.explain(skill) } }
        .halign(.start)
    }
  }

  @ViewBuilder private var locations: Body {
    let created = skill.created(usage: store.usage[skill.id])
    if created != .distantPast {
      paragraph("Created \(created.formatted(.dateTime.day().month(.wide).year()))").dimLabel()
    }
    ForEach(skill.copies) { copy in
      HStack(spacing: 10) {
        VStack(spacing: 2) {
          paragraph(copy.sourceLabel).heading()
          paragraph(copy.isSymlink ? "\(Paths.abbreviate(copy.folder)) → \(Paths.abbreviate(copy.resolved))" : Paths.abbreviate(copy.folder), selectable: true)
            .monospace()
            .caption()
            .dimLabel()
        }
        .hexpand()
        Button("Show in Files") { Desktop.reveal(copy.folder) }
          .flat()
          .valign(.center)
        if skill.removableCopies.count > 1, skill.removableCopies.contains(copy) {
          Button("Remove") { store.removal = .copy(copy, of: skill) }
            .flat()
            .valign(.center)
        }
      }
    }
    if skill.copiesDiffer {
      paragraph("These copies have different content, so editing one won't update the others.").warning()
    }
    if skill.isPersonal {
      HStack(spacing: 10) {
        Button("Rename…") { store.renaming = skill }
        Button("Uninstall this skill") { store.removal = .uninstall(skill) }
          .destructive()
      }
      .halign(.start)
    } else if let plugin = skill.copies.first(where: { $0.root.kind == .plugin }) {
      paragraph("It comes from the \(plugin.sourceLabel), so uninstall the plugin to remove it.").dimLabel()
    }
  }

  @ViewBuilder private var file: Body {
    HStack(spacing: 6) {
      if skill.isPersonal {
        Button("Edit") { store.editing = skill }.flat()
      }
      Button("Open in Editor") { Desktop.open(skill.skillFile) }.flat()
    }
    .halign(.start)
    paragraph(SkillText.read(skill.skillFile), selectable: true)
      .monospace()
      .style("file-preview")
      .card()
  }
}

/// Re-renders read the SKILL.md again only when its size or date changed.
@MainActor
enum SkillText {
  private static var cache: [URL: (stamp: String, text: String)] = [:]

  static func read(_ url: URL) -> String {
    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    let stamp = "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)-\(values?.fileSize ?? 0)"
    if let cached = cache[url], cached.stamp == stamp { return cached.text }
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    cache[url] = (stamp, text)
    return text
  }
}
