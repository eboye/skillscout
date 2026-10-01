import Foundation

/// A skill as `skillscout --json` and `skillscoutctl` print it.
struct SkillJSON: Encodable {
  struct Copy: Encodable {
    let path: String
    let source: String
    let linksTo: String?
  }

  let name: String
  let description: String
  let personal: Bool
  let availableIn: [String]
  let missingIn: [String]
  let chats: Int
  let chatsByTool: [String: Int]
  let lastUsed: Date?
  let projects: [String]
  let created: Date?
  let skillFile: String
  let copies: [Copy]
  var explanation: String?
  var text: String?

  init(_ skill: Skill, tools: [Tool], usage: SkillUsage?) {
    name = skill.name
    description = skill.description
    personal = skill.isPersonal
    availableIn = tools.filter(skill.availableIn.contains).map(\.rawValue)
    missingIn = skill.missing(from: tools).map(\.rawValue)
    chats = usage?.chats ?? 0
    chatsByTool = Dictionary(uniqueKeysWithValues: (usage?.byTool ?? [:]).map { ($0.key.rawValue, $0.value) })
    lastUsed = usage?.lastUsed
    projects = usage?.topProjects ?? []
    let createdDate = skill.created(usage: usage)
    created = createdDate == .distantPast ? nil : createdDate
    skillFile = skill.skillFile.path
    copies = skill.copies.map {
      Copy(path: $0.folder.path, source: $0.sourceLabel, linksTo: $0.isSymlink ? $0.resolved.path : nil)
    }
  }
}

func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  encoder.dateEncodingStrategy = .iso8601
  return try encoder.encode(value)
}
