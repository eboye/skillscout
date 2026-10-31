import Foundation

// The view-independent parts of the SwiftUI files, which Linux can't compile because they import
// SwiftUI. Keep them in step with ContentView.swift, SkillViews.swift, SimilarViews.swift and
// Components.swift.

enum SidebarItem: Hashable {
  case allSkills
  case missing
  case unused
  case tool(Tool)
  case suggestions
  case similar

  var listsSkills: Bool { self != .suggestions && self != .similar }
}

enum SkillSource: String, CaseIterable, Identifiable, CustomStringConvertible {
  case yours, plugin, builtIn, all

  var id: String { rawValue }

  var description: String {
    switch self {
    case .yours: "Your skills"
    case .plugin: "Plugin skills"
    case .builtIn: "Built-in skills"
    case .all: "All skills"
    }
  }

  func includes(_ skill: Skill) -> Bool {
    switch self {
    case .yours: skill.isPersonal
    case .plugin: !skill.isPersonal && skill.copies.contains { $0.root.kind == .plugin }
    case .builtIn: !skill.isPersonal && skill.copies.contains { $0.root.kind == .builtIn }
    case .all: true
    }
  }
}

extension SkillSort: Identifiable, CustomStringConvertible {
  var id: String { rawValue }

  var description: String {
    switch self {
    case .newest: "Newest first"
    case .name: "Sort by name"
    case .use: "Sort by use"
    }
  }
}

extension Tool {
  var shortName: String {
    switch self {
    case .cursor: "Cursor"
    case .claude: "Claude"
    case .codex: "Codex"
    case .gemini: "Gemini"
    case .opencode: "OpenCode"
    case .droid: "Droid"
    case .pi: "Pi"
    case .amp: "Amp"
    }
  }

  /// Two letters for the small badges in a row, like the command's `list` columns.
  var code: String {
    switch self {
    case .cursor: "Cu"
    case .claude: "Cl"
    case .codex: "Co"
    case .gemini: "Ge"
    case .opencode: "Op"
    case .droid: "Dr"
    case .pi: "Pi"
    case .amp: "Am"
    }
  }

  /// The macOS app's colors, from the GNOME palette.
  var color: String {
    switch self {
    case .cursor: "#7a5ce6"
    case .claude: "#e66100"
    case .codex: "#2190a4"
    case .gemini: "#3584e4"
    case .opencode: "#2ec27e"
    case .droid: "#986a44"
    case .pi: "#9141ac"
    case .amp: "#e0478f"
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
    var sentences = ["Skillscout moves it to the Trash from \(folders.formatted(.list(type: .and)))."]

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

extension SkillInstaller.MergePlan {
  /// What happens, in two sentences, before you ask AI for the merged SKILL.md.
  func summary(tools: [Tool]) -> String {
    var sentences = ["\(kept.name) keeps its \(folders.count == 1 ? "folder" : "folders") and gets one SKILL.md written from both. \(merged.name) goes to the Trash."]
    let gained = toolsGained(tools)
    if !gained.isEmpty {
      sentences.append("\(gained.map(\.name).formatted(.list(type: .and))) will load \(kept.name) instead.")
    }
    return sentences.joined(separator: " ")
  }

  /// Every change, with the folders, for the confirmation.
  func message(tools: [Tool]) -> String {
    let places = folders.map(Paths.abbreviate).formatted(.list(type: .and))
    var sentences = ["Skillscout writes the merged SKILL.md into \(places), and moves the old \(folders.count == 1 ? "one" : "ones") to the Trash."]
    if !copiedFiles.isEmpty {
      sentences.append("It copies over \(plural(copiedFiles.count, "file")) from \(merged.name).")
    }
    if skippedFiles.count == 1 {
      sentences.append("\(skippedFiles[0]) from \(merged.name) stays out, because \(kept.name) has its own.")
    } else if !skippedFiles.isEmpty {
      sentences.append("\(skippedFiles.count) files from \(merged.name) stay out, because \(kept.name) has its own at the same paths.")
    }

    let removedFrom = merged.removableCopies.map { Paths.abbreviate($0.root.url) }.formatted(.list(type: .and))
    sentences.append("\(merged.name) goes to the Trash from \(removedFrom).")
    let targets = merged.linkTargetsKept(merged.removableCopies)
    if !targets.isEmpty {
      sentences.append("\(targets.map(Paths.abbreviate).formatted(.list(type: .and))), where its links point, \(targets.count == 1 ? "stays where it is" : "stay where they are").")
    }

    let gained = toolsGained(tools)
    if !gained.isEmpty {
      let linked = links.map { Paths.abbreviate($0.deletingLastPathComponent()) }.formatted(.list(type: .and))
      sentences.append("A link in \(linked) makes \(gained.map(\.name).formatted(.list(type: .and))) load \(kept.name) instead.")
    }
    return sentences.joined(separator: " ")
  }
}

/// SwiftUI's `^[\(count) chat](inflect: true)`, which Linux doesn't have.
func plural(_ count: Int, _ word: String) -> String {
  "\(count.formatted()) \(word)\(count == 1 ? "" : "s")"
}

func relative(_ date: Date) -> String {
  date.formatted(.relative(presentation: .named, unitsStyle: .wide))
}

func list(_ items: [String]) -> String {
  items.formatted(.list(type: .and))
}
