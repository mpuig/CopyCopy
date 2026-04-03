import Foundation

@MainActor
final class UsageHistory {
    static let shared = UsageHistory()

    private var entries: [Entry] = []
    private let filePath: URL

    struct Entry: Codable {
        let skillId: String
        let contentKind: String
        let sourceContext: String
        var count: Int
        var lastUsed: Date
    }

    private init() {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/copycopy")
        filePath = cacheDir.appendingPathComponent("usage-history.json")
        load()
    }

    func record(skillId: String, contentKind: ClipboardContentKind, sourceContext: SourceAppContext) {
        let key = entryKey(skillId: skillId, contentKind: contentKind, sourceContext: sourceContext)

        if let index = entries.firstIndex(where: { entryKey(for: $0) == key }) {
            entries[index].count += 1
            entries[index].lastUsed = Date()
        } else {
            entries.append(Entry(
                skillId: skillId,
                contentKind: contentKind.rawValue,
                sourceContext: sourceContext.rawValueString,
                count: 1,
                lastUsed: Date()
            ))
        }

        save()
    }

    func boost(for skillId: String, contentKind: ClipboardContentKind, sourceContext: SourceAppContext) -> Int {
        let count = count(for: skillId, contentKind: contentKind, sourceContext: sourceContext)
        return min(50, count * 10)
    }

    func count(for skillId: String, contentKind: ClipboardContentKind, sourceContext: SourceAppContext) -> Int {
        let key = entryKey(skillId: skillId, contentKind: contentKind, sourceContext: sourceContext)
        return entries.first(where: { entryKey(for: $0) == key })?.count ?? 0
    }

    private func entryKey(skillId: String, contentKind: ClipboardContentKind, sourceContext: SourceAppContext) -> String {
        "\(skillId)|\(contentKind.rawValue)|\(sourceContext.rawValueString)"
    }

    private func entryKey(for entry: Entry) -> String {
        "\(entry.skillId)|\(entry.contentKind)|\(entry.sourceContext)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: filePath),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(entries) else { return }

        let dir = filePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: filePath, options: .atomic)
    }
}

extension SourceAppContext {
    var rawValueString: String {
        switch self {
        case .terminal: return "terminal"
        case .email: return "email"
        case .chat: return "chat"
        case .notes: return "notes"
        case .ide: return "ide"
        case .browser: return "browser"
        case .other: return "other"
        }
    }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .email: return "Email"
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .ide: return "IDE"
        case .browser: return "Browser"
        case .other: return "Other"
        }
    }
}
