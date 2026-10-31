import Foundation
import Testing

@testable import skillscout

/// A made-up home for the whole run. `Paths.home` reads `$HOME` once, so it has to be set before
/// anything touches `Paths`, and every test starts by asking for it.
let fakeHome: URL = {
  let home = FileManager.default.temporaryDirectory.appending(path: "skillscout-tests-\(UUID().uuidString)")
  try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  setenv("HOME", home.path, 1)
  setenv("XDG_DATA_HOME", home.appending(path: ".local/share").path, 1)
  setenv("XDG_CONFIG_HOME", home.appending(path: ".config").path, 1)
  unsetenv("FLATPAK_ID")
  return home
}()

/// Empties the made-up home, so each test starts with no skills.
func freshHome() throws -> URL {
  let fm = FileManager.default
  for entry in try fm.contentsOfDirectory(atPath: fakeHome.path) {
    try fm.removeItem(at: fakeHome.appending(path: entry))
  }
  #expect(Paths.home.standardizedFileURL.path == fakeHome.standardizedFileURL.path)
  return fakeHome
}

@discardableResult
func writeSkill(_ relativeFolder: String, name: String? = nil, description: String, body: String = "Do the thing.") throws -> URL {
  let folder = fakeHome.appending(path: relativeFolder)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let nameLine = name.map { "name: \($0)\n" } ?? ""
  try "---\n\(nameLine)description: \(description)\n---\n\n\(body)\n"
    .write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
  return folder
}

func link(_ relative: String, to target: URL) throws {
  let url = fakeHome.appending(path: relative)
  try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
}

func exists(_ relative: String) -> Bool {
  (try? FileManager.default.attributesOfItem(atPath: fakeHome.appending(path: relative).path)) != nil
}

@Suite("Frontmatter")
struct FrontmatterTests {
  @Test func readsKeysAndFoldedValues() {
    let text = "---\nname: \"release-notes\"\ndescription: >\n  Write the notes\n  for a release.\n---\nBody\n"
    let meta = Frontmatter.parse(text)
    #expect(meta["name"] == "release-notes")
    #expect(meta["description"] == "Write the notes for a release.")
    #expect(Frontmatter.body(of: text) == "Body\n")
  }

  @Test func withoutFrontmatter() {
    #expect(Frontmatter.parse("Just text").isEmpty)
    #expect(Frontmatter.body(of: "Just text") == "Just text")
    #expect(Frontmatter.setting(name: "x", in: "Just text") == "Just text")
  }

  @Test func settingNameReplacesOrInserts() {
    #expect(Frontmatter.setting(name: "new", in: "---\nname: old\ndescription: d\n---\n") == "---\nname: new\ndescription: d\n---\n")
    #expect(Frontmatter.setting(name: "new", in: "---\ndescription: d\n---\n") == "---\nname: new\ndescription: d\n---\n")
  }

  @Test func slug() {
    #expect(SkillInstaller.slug("Release Notes!") == "release-notes")
    #expect(SkillInstaller.slug("--a__b--") == "a-b")
  }
}

@Suite("On disk", .serialized)
struct DiskTests {
  @Test func linkedSkillIsOneSkillLoadedByBothFolders() throws {
    _ = try freshHome()
    let folder = try writeSkill(".agents/skills/deploy", description: "Deploy the site.")
    try link(".claude/skills/deploy", to: folder)

    let skills = SkillScanner.scan()
    let skill = try #require(skills.first { $0.name == "deploy" })
    #expect(skills.count == 1)
    #expect(skill.copies.count == 2)
    #expect(skill.availableIn.isSuperset(of: [.claude, .codex, .cursor, .gemini]))
    #expect(skill.missing(from: Tool.allCases) == [.amp])
    #expect(!skill.copiesDiffer)
    #expect(skill.copies.filter(\.isSymlink).count == 1)
  }

  @Test func copiesWithDifferentTextAreFlagged() throws {
    _ = try freshHome()
    try writeSkill(".agents/skills/deploy", description: "Deploy the site.")
    try writeSkill(".claude/skills/deploy", description: "Deploy the site, but differently.")

    let skill = try #require(SkillScanner.scan().first)
    #expect(skill.copies.count == 2)
    #expect(skill.copiesDiffer)
  }

  @Test func nameComesFromFrontmatterThenFolder() throws {
    _ = try freshHome()
    try writeSkill(".agents/skills/folder-name", name: "real-name", description: "A.")
    try writeSkill(".agents/skills/plain", description: "B.")

    #expect(SkillScanner.scan().map(\.name) == ["plain", "real-name"])
  }

  @Test func disabledClaudePluginIsSkipped() throws {
    let home = try freshHome()
    try writeSkill(".claude/plugins/cache/market/on-plugin/1.0.0/skills/on", description: "On.")
    try writeSkill(".claude/plugins/cache/market/off-plugin/1.0.0/skills/off", description: "Off.")
    try #"{"enabledPlugins": {"off-plugin@market": false}}"#
      .write(to: home.appending(path: ".claude/settings.json"), atomically: true, encoding: .utf8)

    let skills = SkillScanner.scan()
    #expect(skills.map(\.name) == ["on"])
    #expect(skills.first?.primary.pluginName == "on-plugin")
    #expect(skills.first?.isPluginOnly == true)
  }

  @Test func addLinksIntoAnotherAgent() throws {
    _ = try freshHome()
    let folder = try writeSkill(".claude/skills/deploy", description: "Deploy.")
    let skill = try #require(SkillScanner.scan().first)

    let destination = try SkillInstaller.add(skill, to: .amp)
    #expect(destination.path == fakeHome.appending(path: ".config/agents/skills/deploy").path)
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
    #expect(URL(fileURLWithPath: target).standardizedFileURL.path == folder.standardizedFileURL.path)
    #expect(SkillScanner.scan().first?.availableIn.contains(.amp) == true)
    #expect(throws: (any Error).self) { try SkillInstaller.add(skill, to: .amp) }
  }

  @Test func removingAFolderTakesItsLinksToTheTrash() throws {
    _ = try freshHome()
    let folder = try writeSkill(".agents/skills/deploy", description: "Deploy.")
    try link(".claude/skills/deploy", to: folder)
    let skill = try #require(SkillScanner.scan().first)
    let original = try #require(skill.copies.first { !$0.isSymlink })

    let going = skill.copiesGoing(with: original)
    #expect(going.count == 2)
    #expect(skill.toolsLosing(going) == skill.availableIn)
    try SkillInstaller.remove(going)

    #expect(!exists(".agents/skills/deploy"))
    #expect(!exists(".claude/skills/deploy"))
    #expect(SkillScanner.scan().isEmpty)
    let trashed = try FileManager.default.contentsOfDirectory(atPath: fakeHome.appending(path: ".local/share/Trash/info").path)
    #expect(trashed.count == 2)
  }

  @Test func removingOnlyTheLinkKeepsTheFolder() throws {
    _ = try freshHome()
    let folder = try writeSkill(".agents/skills/deploy", description: "Deploy.")
    try link(".claude/skills/deploy", to: folder)
    let skill = try #require(SkillScanner.scan().first)
    let linkCopy = try #require(skill.copies.first { $0.isSymlink })

    #expect(skill.copiesGoing(with: linkCopy) == [linkCopy])
    #expect(skill.toolsLosing([linkCopy]) == [.claude])
    try SkillInstaller.remove([linkCopy])
    #expect(exists(".agents/skills/deploy/SKILL.md"))
    #expect(!exists(".claude/skills/deploy"))
  }

  @Test func pluginCopiesCantBeRemoved() throws {
    _ = try freshHome()
    try writeSkill(".claude/plugins/cache/market/p/1.0.0/skills/plugged", description: "P.")
    let skill = try #require(SkillScanner.scan().first)
    #expect(throws: (any Error).self) { try SkillInstaller.remove(skill.copies) }
    #expect(exists(".claude/plugins/cache/market/p/1.0.0/skills/plugged/SKILL.md"))
  }

  @Test func renameMovesFoldersRelinksAndRewritesTheName() throws {
    _ = try freshHome()
    let folder = try writeSkill(".agents/skills/deploy", name: "deploy", description: "Deploy.")
    try link(".claude/skills/deploy", to: folder)
    let skills = SkillScanner.scan()
    let skill = try #require(skills.first)

    #expect(SkillInstaller.renameProblem(skill, to: "Ship It", among: skills) != nil)
    #expect(SkillInstaller.renameProblem(skill, to: "deploy", among: skills) != nil)
    try SkillInstaller.rename(skill, to: "ship-it", among: skills)

    #expect(!exists(".agents/skills/deploy"))
    let renamed = try #require(SkillScanner.scan().first)
    #expect(renamed.name == "ship-it")
    #expect(renamed.copies.count == 2)
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: fakeHome.appending(path: ".claude/skills/ship-it").path)
    #expect(target.hasSuffix(".agents/skills/ship-it"))
    #expect(SkillAliases.load()["deploy"] == "ship-it")
  }

  @Test func saveEverywhereLinksOnlyTheAgentsTheSharedFolderMisses() throws {
    _ = try freshHome()
    let folder = try SkillInstaller.save(
      markdown: "---\nname: New Skill\ndescription: N.\n---\n",
      fallbackName: "unused",
      to: .everywhere([.claude, .codex, .amp, .cursor])
    )
    #expect(folder.lastPathComponent == "new-skill")
    #expect(exists(".agents/skills/new-skill/SKILL.md"))
    #expect(exists(".claude/skills/new-skill"))
    #expect(exists(".config/agents/skills/new-skill"))
    #expect(!exists(".codex/skills/new-skill"))
    #expect(!exists(".cursor/skills/new-skill"))
    #expect(SkillScanner.scan().first?.missing(from: [.claude, .codex, .amp, .cursor]).isEmpty == true)
  }
}

// Similarity and usage read the same made-up home, so they run in the same serialized suite.
extension DiskTests {
  @Test func pairsSkillsThatReadAlike() throws {
    _ = try freshHome()
    try writeSkill(".agents/skills/deploy-site", description: "Build the static site and deploy it to the production server with rsync.", body: "Run the static site build, then rsync the output folder to the production server.")
    try writeSkill(".agents/skills/ship-site", description: "Build the static site and deploy it to the production server with rsync.", body: "Run the static site build, then rsync the output folder to the production server.")
    try writeSkill(".agents/skills/email-style", description: "Write emails in a friendly tone.", body: "Keep emails short, warm and clear.")

    let skills = SkillScanner.scan()
    let pairs = SkillSimilarity.pairs(in: skills)
    #expect(pairs.count == 1)
    let pair = try #require(pairs.first)
    #expect(Set([pair.first, pair.second]) == ["deploy-site", "ship-site"])
    #expect(pair.other(than: "deploy-site") == "ship-site")

    let dismissed: Set<String> = [SimilarPair.key("ship-site", "deploy-site")]
    #expect(SkillSimilarity.pairs(in: skills, dismissed: dismissed).isEmpty)
  }
}

extension DiskTests {
  @Test func countsEachChatOnceAndFollowsRenames() throws {
    _ = try freshHome()
    let folder = try writeSkill(".agents/skills/ship-it", description: "Ship.")
    let skills = SkillScanner.scan()
    let early = Date(timeIntervalSince1970: 1_000)
    let late = Date(timeIntervalSince1970: 2_000)
    let uses = [
      SkillUse(tool: .claude, chat: "a", project: "web", date: late, folder: folder.path),
      SkillUse(tool: .claude, chat: "a", project: "web", date: late, folder: folder.path),
      SkillUse(tool: .codex, chat: "b", project: "api", date: early, folder: "deploy"),
      SkillUse(tool: .codex, chat: "c", project: "api", date: early, folder: "unknown-skill"),
    ]

    let usage = try #require(SkillUsage.tally(uses, skills: skills, aliases: ["deploy": "ship-it"])["ship-it"])
    #expect(usage.chats == 2)
    #expect(usage.byTool == [.claude: 1, .codex: 1])
    #expect(usage.firstUsed == early)
    #expect(usage.lastUsed == late)
    #expect(usage.topProjects == ["api", "web"])
    #expect(SkillUsage.tally(uses, skills: skills)["ship-it"]?.chats == 1)
  }
}

extension DiskTests {
  func writeSettings(_ settings: [String: Any], to relative: String) throws {
    let url = fakeHome.appending(path: relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0).write(to: url)
  }

  @Test func adoptsTheFormerSettings() throws {
    _ = try freshHome()
    try writeSettings(["tools": ["claude", "codex"]], to: ".config/\(AppID.former).plist")

    AppID.adoptFormerData()
    #expect(exists(".config/\(AppID.current).plist"))
    // UserDefaults itself can't be checked here: CoreFoundation took the environment when the test
    // process started, so it still looks at the real ~/.config. Never write settings from a test.

    // A second start leaves the new settings alone.
    try writeSettings(["tools": ["amp"]], to: ".config/\(AppID.former).plist")
    AppID.adoptFormerData()
    let kept = try Data(contentsOf: fakeHome.appending(path: ".config/\(AppID.current).plist"))
    let settings = try PropertyListSerialization.propertyList(from: kept, format: nil) as? [String: Any]
    #expect(settings?["tools"] as? [String] == ["claude", "codex"])
  }

  @Test func flatpakAdoptsTheFormerSandbox() throws {
    _ = try freshHome()
    let sandbox = ".var/app/\(AppID.former)"
    try writeSettings(["engine": "claude"], to: "\(sandbox)/config/\(AppID.former).plist")
    try FileManager.default.createDirectory(at: fakeHome.appending(path: "\(sandbox)/data/skillscout"), withIntermediateDirectories: true)
    try "{}".write(to: fakeHome.appending(path: "\(sandbox)/data/skillscout/state.json"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fakeHome.appending(path: ".local/bin"), withIntermediateDirectories: true)
    let wrapper = "#!/bin/sh\nexec flatpak run --command=skillscout \(AppID.former) \"$@\"\n"
    try wrapper.write(to: fakeHome.appending(path: ".local/bin/skillscout"), atomically: true, encoding: .utf8)

    setenv("FLATPAK_ID", AppID.current, 1)
    defer { unsetenv("FLATPAK_ID") }
    AppID.adoptFormerData()

    #expect(exists(".config/\(AppID.current).plist"))
    #expect(FileManager.default.fileExists(atPath: Paths.appSupport.appending(path: "state.json").path))
    let script = try String(contentsOf: fakeHome.appending(path: ".local/bin/skillscout"), encoding: .utf8)
    #expect(script.contains("flatpak run --command=skillscout \(AppID.current) "))
    #expect(!script.contains(AppID.former))
  }

  @Test func outsideTheFlatpakTheDataStaysPut() throws {
    _ = try freshHome()
    try FileManager.default.createDirectory(at: fakeHome.appending(path: ".var/app/\(AppID.former)/data/skillscout"), withIntermediateDirectories: true)
    try "{}".write(to: fakeHome.appending(path: ".var/app/\(AppID.former)/data/skillscout/state.json"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)

    AppID.adoptFormerData()
    #expect(!FileManager.default.fileExists(atPath: Paths.appSupport.appending(path: "state.json").path))
  }
}
