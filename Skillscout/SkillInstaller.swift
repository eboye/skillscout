import Foundation

enum SaveTarget: Hashable {
  case everywhere([Tool])
  case tool(Tool)
}

enum SkillInstaller {
  enum Failure: LocalizedError {
    case alreadyExists(URL)
    case builtIn(String)

    var errorDescription: String? {
      switch self {
      case .alreadyExists(let url): "\(Paths.abbreviate(url)) already exists."
      case .builtIn(let name): "\(name) is built into its tool and can't be moved."
      }
    }
  }

  static func add(_ skill: Skill, to tool: Tool) throws -> URL {
    guard let source = skill.copies.first(where: { $0.root.kind != .builtIn }) else {
      throw Failure.builtIn(skill.name)
    }
    let fm = FileManager.default
    try fm.createDirectory(at: tool.skillsFolder, withIntermediateDirectories: true)
    let destination = tool.skillsFolder.appending(path: source.resolved.lastPathComponent)
    guard !exists(destination) else { throw Failure.alreadyExists(destination) }

    if source.root.kind == .plugin {
      try fm.copyItem(at: source.resolved, to: destination)
    } else {
      try fm.createSymbolicLink(at: destination, withDestinationURL: source.resolved)
    }
    return destination
  }

  static func save(markdown: String, fallbackName: String, to target: SaveTarget) throws -> URL {
    let name = slug(Frontmatter.parse(markdown)["name"] ?? fallbackName)
    let fm = FileManager.default

    let shared = SkillRoot.all[0]
    let folder: URL
    switch target {
    case .everywhere: folder = shared.url.appending(path: name)
    case .tool(let tool): folder = tool.skillsFolder.appending(path: name)
    }
    guard !exists(folder) else { throw Failure.alreadyExists(folder) }
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try markdown.write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    if case .everywhere(let tools) = target {
      for tool in linkTargets(for: tools) {
        let link = tool.skillsFolder.appending(path: name)
        if !exists(link) {
          try fm.createDirectory(at: tool.skillsFolder, withIntermediateDirectories: true)
          try fm.createSymbolicLink(at: link, withDestinationURL: folder)
        }
      }
    }
    return folder
  }

  /// Tools that don't read the shared folder, so saving everywhere links the skill into their own folder.
  static func linkTargets(for tools: [Tool]) -> [Tool] {
    var covered = SkillRoot.all[0].readBy
    return tools.filter { tool in
      guard !covered.contains(tool) else { return false }
      covered.formUnion(SkillRoot.all.first { $0.url == tool.skillsFolder }?.readBy ?? [tool])
      return true
    }
  }

  private static func exists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
  }

  static func slug(_ text: String) -> String {
    let lowered = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
    return String(lowered)
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }
}
