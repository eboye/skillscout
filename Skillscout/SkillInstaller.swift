import Foundation

enum SaveTarget: Hashable {
  case everywhere([Tool])
  case tool(Tool)
}

enum SkillInstaller {
  enum Failure: LocalizedError {
    case alreadyExists(URL)
    case builtIn(String)
    case managed(URL)
    case changedOnDisk(URL)
    case problem(String)

    var errorDescription: String? {
      switch self {
      case .alreadyExists(let url): "\(Paths.abbreviate(url)) already exists."
      case .builtIn(let name): "\(name) is built into its tool and can't be moved."
      case .managed(let url): "\(Paths.abbreviate(url)) belongs to a plugin or to its tool, so Skill Cabinet leaves it alone."
      case .changedOnDisk(let url): "\(Paths.abbreviate(url)) changed since you started editing it."
      case .problem(let problem): problem
      }
    }
  }

  // MARK: - Edit

  /// An edit of a skill's SKILL.md. It covers every personal copy with the same text, so they stay alike.
  struct Edit: Sendable {
    let skill: Skill
    let files: [URL]
    let original: String
    /// Personal copies whose SKILL.md has other text. The edit leaves them as they are.
    let otherFiles: [URL]
  }

  static func edit(_ skill: Skill) throws -> Edit {
    let copies = skill.removableCopies.filter { !isManaged($0.resolved) }
    guard let source = copies.first else { throw Failure.managed(skill.primary.resolved) }
    let original = try String(contentsOf: skillFile(source), encoding: .utf8)
    var files: [URL] = []
    var otherFiles: [URL] = []
    for file in copies.map(skillFile) where !files.contains(file) && !otherFiles.contains(file) {
      if (try? String(contentsOf: file, encoding: .utf8)) == original {
        files.append(file)
      } else {
        otherFiles.append(file)
      }
    }
    return Edit(skill: skill, files: files, original: original, otherFiles: otherFiles)
  }

  /// Why `text` can't be saved, or nil when it can. The name stays, since renaming moves folders too.
  static func editProblem(_ edit: Edit, text: String) -> String? {
    let meta = Frontmatter.parse(text)
    let before = Frontmatter.parse(edit.original)
    let name = meta["name"].flatMap { $0.isEmpty ? nil : $0 }
    if name != edit.skill.name, name != nil || !before["name", default: ""].isEmpty {
      return "Keep name: \(edit.skill.name) in the frontmatter. To change the name, use Rename."
    }
    if meta["description", default: ""].isEmpty, !before["description", default: ""].isEmpty {
      return "Keep a description in the frontmatter, so agents know when to use the skill."
    }
    return nil
  }

  /// Writes `text` into every SKILL.md of the edit. It stops when one of them changed since the edit started,
  /// unless `overwrite` is set.
  static func save(_ edit: Edit, text: String, overwrite: Bool = false) throws {
    if let problem = editProblem(edit, text: text) { throw Failure.problem(problem) }
    if !overwrite, let changed = edit.files.first(where: { (try? String(contentsOf: $0, encoding: .utf8)) != edit.original }) {
      throw Failure.changedOnDisk(changed)
    }
    for file in edit.files {
      try text.write(to: file, atomically: true, encoding: .utf8)
    }
  }

  /// The SKILL.md of a copy, with links followed, so writing it doesn't replace a link with a file.
  private static func skillFile(_ copy: SkillCopy) -> URL {
    copy.resolved.appending(path: "SKILL.md").resolvingSymlinksInPath()
  }

  // MARK: - Rename

  /// Why `skill` can't be called `name`, or nil when it can.
  static func renameProblem(_ skill: Skill, to name: String, among skills: [Skill]) -> String? {
    if name.isEmpty { return "Type a name." }
    if name != slug(name) {
      let example = slug(name).isEmpty ? "release-notes" : slug(name)
      return "Use lowercase letters, numbers and hyphens, like \(example)."
    }
    if name.count > 64 { return "Keep it under 64 characters." }
    if name == skill.name { return "It's already called \(name)." }
    if skills.contains(where: { $0.name.lowercased() == name }) { return "There's already a skill called \(name)." }
    for copy in skill.removableCopies {
      let destination = renamed(copy, to: name)
      if destination != copy.folder, exists(destination) { return "\(Paths.abbreviate(destination)) already exists." }
    }
    return nil
  }

  /// Gives a skill a new name. Its folders in your skills folders get the new name, the links get re-created
  /// under it, and each SKILL.md gets the new `name`. Plugin and built-in copies keep the old name, and so
  /// do the folders that links point to outside your skills folders.
  static func rename(_ skill: Skill, to name: String, among skills: [Skill]) throws {
    if let problem = renameProblem(skill, to: name, among: skills) { throw Failure.problem(problem) }
    let copies = skill.removableCopies
    guard !copies.isEmpty else { throw Failure.managed(skill.primary.folder) }
    if let managed = copies.first(where: { isManaged($0.resolved) }) { throw Failure.managed(managed.resolved) }

    let fm = FileManager.default
    var moved: [URL: URL] = [:]
    for copy in copies where !copy.isSymlink {
      let destination = renamed(copy, to: name)
      if destination != copy.folder { try fm.moveItem(at: copy.folder, to: destination) }
      moved[copy.resolved] = destination.resolvingSymlinksInPath()
    }
    for copy in copies where copy.isSymlink {
      try fm.removeItem(at: copy.folder)
      try fm.createSymbolicLink(at: renamed(copy, to: name), withDestinationURL: moved[copy.resolved] ?? copy.resolved)
    }
    for folder in Set(copies.map { moved[$0.resolved] ?? $0.resolved }) {
      let file = folder.appending(path: "SKILL.md")
      let text = try String(contentsOf: file, encoding: .utf8)
      try Frontmatter.setting(name: name, in: text).write(to: file, atomically: true, encoding: .utf8)
    }
    SkillAliases.record(skill.name, as: name)
  }

  private static func renamed(_ copy: SkillCopy, to name: String) -> URL {
    copy.folder.deletingLastPathComponent().appending(path: name)
  }

  // MARK: - Merge

  /// What merging one skill into another changes on disk, worked out before anything changes.
  struct MergePlan: Sendable {
    let kept: Skill
    let merged: Skill
    /// The folders that get the merged SKILL.md. Their old SKILL.md goes to the Trash.
    let folders: [URL]
    /// The folder the merged skill's other files come from.
    let source: URL
    /// The kept skill's files besides SKILL.md, as paths inside its folder.
    let keptFiles: [String]
    /// The merged skill's files that get copied into `folders`.
    let copiedFiles: [String]
    /// The merged skill's files that stay out, because the kept skill has a file at the same path.
    let skippedFiles: [String]
    /// The skills folders that get a link to the kept skill in place of the merged one, so no tool loses it.
    let linkRoots: [SkillRoot]

    var id: String { "\(merged.name)>\(kept.name)" }

    var links: [URL] { linkRoots.map { $0.url.appending(path: kept.name) } }

    /// The tools that load the kept skill instead of the merged one, once it's done.
    func toolsGained(_ tools: [Tool]) -> [Tool] {
      tools.filter { tool in !kept.availableIn.contains(tool) && linkRoots.contains { $0.readBy.contains(tool) } }
    }
  }

  static func planMerge(_ merged: Skill, into kept: Skill) throws -> MergePlan {
    guard merged != kept else { throw Failure.problem("A skill can't be merged into itself.") }
    guard let keptCopy = kept.removableCopies.first else { throw Failure.managed(kept.primary.folder) }
    guard let mergedCopy = merged.removableCopies.first(where: { !$0.isSymlink }) ?? merged.removableCopies.first else {
      throw Failure.managed(merged.primary.folder)
    }
    var folders: [URL] = []
    for copy in kept.removableCopies where !folders.contains(copy.resolved) {
      if isManaged(copy.resolved) { throw Failure.managed(copy.resolved) }
      folders.append(copy.resolved)
    }

    let keptFiles = supportFiles(in: keptCopy.resolved)
    let incoming = supportFiles(in: mergedCopy.resolved)

    var covered = kept.availableIn
    var linkRoots: [SkillRoot] = []
    for root in merged.removableCopies.map(\.root) where !root.readBy.isSubset(of: covered) {
      let link = root.url.appending(path: kept.name)
      if exists(link), !merged.removableCopies.contains(where: { $0.folder == link }) { throw Failure.alreadyExists(link) }
      linkRoots.append(root)
      covered.formUnion(root.readBy)
    }

    return MergePlan(
      kept: kept,
      merged: merged,
      folders: folders,
      source: mergedCopy.resolved,
      keptFiles: keptFiles,
      copiedFiles: incoming.filter { !keptFiles.contains($0) },
      skippedFiles: incoming.filter(keptFiles.contains),
      linkRoots: linkRoots
    )
  }

  /// Makes `markdown` the SKILL.md of the kept skill, brings over the merged skill's other files,
  /// moves the merged skill to the Trash, and links the kept one where the merged one was.
  static func merge(_ plan: MergePlan, markdown: String) throws {
    let fm = FileManager.default
    let text = Frontmatter.setting(name: plan.kept.name, in: markdown)
    for folder in plan.folders {
      for path in plan.copiedFiles where !exists(folder.appending(path: path)) {
        let destination = folder.appending(path: path)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: plan.source.appending(path: path), to: destination)
      }
      let file = folder.appending(path: "SKILL.md")
      try fm.trashItem(at: file, resultingItemURL: nil)
      try text.write(to: file, atomically: true, encoding: .utf8)
    }
    try remove(plan.merged.removableCopies)
    for link in plan.links {
      try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fm.createSymbolicLink(at: link, withDestinationURL: plan.folders[0])
    }
    SkillAliases.record(plan.merged.name, as: plan.kept.name)
  }

  /// The files in a skill folder besides SKILL.md, as paths inside it. Hidden files stay out.
  static func supportFiles(in folder: URL) -> [String] {
    let fm = FileManager.default
    let paths = (try? fm.subpathsOfDirectory(atPath: folder.path)) ?? []
    return paths.filter { path in
      var isFolder: ObjCBool = false
      return path != "SKILL.md"
        && !path.split(separator: "/").contains { $0.hasPrefix(".") }
        && fm.fileExists(atPath: folder.appending(path: path).path, isDirectory: &isFolder) && !isFolder.boolValue
    }.sorted()
  }

  /// Whether a folder belongs to a plugin or a tool's built-in skills.
  private static func isManaged(_ folder: URL) -> Bool {
    let path = folder.resolvingSymlinksInPath().path
    return SkillRoot.all.contains { root in
      root.kind != .user && root.kind != .shared && path.hasPrefix(root.url.resolvingSymlinksInPath().path + "/")
    }
  }

  /// Moves the copies to the Trash, so you can put them back from there. A link goes on its own,
  /// and the folder it points to stays.
  static func remove(_ copies: [SkillCopy]) throws {
    if let managed = copies.first(where: { $0.root.kind != .user && $0.root.kind != .shared }) {
      throw Failure.managed(managed.folder)
    }
    for copy in copies {
      try FileManager.default.trashItem(at: copy.folder, resultingItemURL: nil)
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
