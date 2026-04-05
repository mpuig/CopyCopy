import Foundation

/// Persistent learning system for clipboard action patterns.
/// Stores user preferences and action history in ~/.copycopy/ as markdown files.
@MainActor
final class SkillMemory {
    static let shared = SkillMemory()

    private let baseDir: URL
    private let memoryFile: URL
    private let memoryDir: URL

    private init() {
        baseDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copycopy")
        memoryFile = baseDir.appendingPathComponent("MEMORY.md")
        memoryDir = baseDir.appendingPathComponent("memory")
        try? FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
    }

    // MARK: - Daily Log

    /// Append an action to the daily log.
    func logAction(skillId: String, skillName: String, sourceApp: SourceAppContext, appName: String? = nil, pipelineHistory: [String] = []) {
        let today = todayFilename()
        let logFile = memoryDir.appendingPathComponent("\(today).md")

        let time = timeFormatter.string(from: Date())
        let source = appName ?? sourceApp.displayName
        let pipeline = pipelineHistory.isEmpty
            ? skillName
            : (pipelineHistory + [skillName]).joined(separator: " → ")

        let entry = "- \(time) | \(source) → \(pipeline)\n"

        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                handle.closeFile()
            }
        } else {
            try? ("# \(today)\n\n" + entry).write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Memory Reading

    /// Read the learned preferences (MEMORY.md contents).
    func readPreferences() -> String {
        (try? String(contentsOf: memoryFile, encoding: .utf8)) ?? ""
    }

    /// Read recent daily log entries (last N days).
    func readRecentLogs(days: Int = 3, maxEntries: Int = 20) -> String {
        var entries: [String] = []
        let calendar = Calendar.current

        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let filename = dateFormatter.string(from: date) + ".md"
            let logFile = memoryDir.appendingPathComponent(filename)

            guard let content = try? String(contentsOf: logFile, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: "\n")
                .filter { $0.hasPrefix("- ") }
            entries.append(contentsOf: lines)
        }

        return Array(entries.suffix(maxEntries)).joined(separator: "\n")
    }

    /// Build context for the LLM follow-up suggestion prompt.
    func buildContext() -> String {
        var parts: [String] = []

        let preferences = readPreferences()
        if !preferences.isEmpty {
            parts.append("User preferences:\n\(preferences)")
        }

        let recentLogs = readRecentLogs()
        if !recentLogs.isEmpty {
            parts.append("Recent actions:\n\(recentLogs)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Memory Writing

    /// Save a learned pattern to MEMORY.md.
    func savePattern(_ pattern: String) {
        var content = readPreferences()

        if content.isEmpty {
            content = "# Learned Preferences\n\n## Patterns\n\n"
        }

        if !content.contains("## Patterns") {
            content += "\n## Patterns\n\n"
        }

        content += "- \(pattern)\n"

        try? content.write(to: memoryFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func todayFilename() -> String {
        dateFormatter.string(from: Date())
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
