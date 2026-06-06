import Foundation

@MainActor
final class SkillLoader {
    private static let orphanedGroupIDs: Set<String> = [
        "urls", "files", "images", "text", "places", "code", "transform", "filesystem",
        "contacts", "social", "tracking", "finance", "datetime", "identity"
    ]

    private var skills: [Skill] = []

    init() {
        exportBuiltInSkillsIfNeeded()
        loadAll()
    }

    func loadAll() {
        var loaded: [Skill] = []

        for (id, content) in BuiltInSkills.all {
            do {
                let parsed = try SkillParser.parseAll(id: id, content: content, isBuiltIn: true)
                loaded.append(contentsOf: parsed)
            } catch {
                Logger.error("Failed to parse built-in skill '\(id)': \(error)", category: .general)
            }
        }

        loadCustomSkills(into: &loaded)
        skills = loaded
        Logger.info("Loaded \(skills.count) skills (\(skills.filter { $0.isBuiltIn }.count) built-in)", category: .general)
    }

    // MARK: - Export Built-in Skills

    private func exportBuiltInSkillsIfNeeded() {
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copycopy/skills")

        removeOrphanedGroupDirectories(in: skillsDir)

        for (id, content) in BuiltInSkills.all {
            do {
                let builtInSkill = try SkillParser.parse(id: id, content: content, isBuiltIn: true)
                let exportedContent = SkillMarkdownFormatter.formatFlat(skill: builtInSkill)
                let dir = skillsDir.appendingPathComponent(id)
                let file = dir.appendingPathComponent("SKILL.md")

                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: file.path) {
                    guard shouldRewriteBuiltInSkillFile(
                        at: file,
                        builtInSkill: builtInSkill,
                        desiredContent: exportedContent
                    ) else {
                        continue
                    }
                }

                try exportedContent.write(to: file, atomically: true, encoding: .utf8)
                Logger.info("Exported built-in skill '\(id)' to \(file.path)", category: .general)
            } catch {
                Logger.error("Failed to export skill '\(id)': \(error)", category: .general)
            }
        }
    }

    private func removeOrphanedGroupDirectories(in skillsDir: URL) {
        for groupID in Self.orphanedGroupIDs {
            let dir = skillsDir.appendingPathComponent(groupID)
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }

            let file = dir.appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

            // Only remove if it's an old grouped format (contains ## Tools or ## Actions)
            if content.contains("## Tools") || content.contains("## Actions") {
                try? FileManager.default.removeItem(at: dir)
                Logger.info("Removed orphaned group directory '\(groupID)'", category: .general)
            }
        }
    }

    private func shouldRewriteBuiltInSkillFile(
        at file: URL,
        builtInSkill: Skill,
        desiredContent: String
    ) -> Bool {
        guard let existingContent = try? String(contentsOf: file, encoding: .utf8) else {
            return true
        }

        if existingContent == desiredContent {
            return false
        }

        do {
            let existingSkill = try SkillParser.parse(
                id: builtInSkill.id,
                content: existingContent,
                isBuiltIn: false
            )
            return isSemanticallyEquivalent(existingSkill, builtInSkill)
        } catch {
            Logger.warning(
                "Skipping rewrite for built-in skill '\(builtInSkill.id)' because the existing file could not be parsed cleanly: \(error)",
                category: .general
            )
            return false
        }
    }

    private func isSemanticallyEquivalent(_ lhs: Skill, _ rhs: Skill) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.description == rhs.description &&
        lhs.icon == rhs.icon &&
        lhs.execute == rhs.execute &&
        lhs.parameters == rhs.parameters &&
        lhs.contentTypes == rhs.contentTypes &&
        lhs.entityTypes == rhs.entityTypes &&
        lhs.sourceContexts == rhs.sourceContexts &&
        lhs.sourceBoosts == rhs.sourceBoosts &&
        lhs.minimumCharacterCount == rhs.minimumCharacterCount &&
        lhs.maximumCharacterCount == rhs.maximumCharacterCount &&
        lhs.tools == rhs.tools &&
        lhs.temperature == rhs.temperature
    }

    func matchingActions(
        for contentKind: ClipboardContentKind,
        sourceContext: SourceAppContext,
        entities: [DetectedEntityType],
        context: ClipboardContext,
        executor: ToolExecutor
    ) -> [SuggestedAction] {
        var ranked: [(skill: Skill, order: Int, score: Int)] = []

        for (order, skill) in skills.enumerated() {
            guard skillMatches(skill, contentKind: contentKind, entities: entities, sourceContext: sourceContext) else {
                continue
            }

            ranked.append((
                skill: skill,
                order: order,
                score: relevanceScore(for: skill, context: context, sourceContext: sourceContext)
            ))
        }

        return ranked
            .sorted {
                if $0.score == $1.score {
                    return $0.order < $1.order
                }
                return $0.score > $1.score
            }
            .map { toSuggestedAction($0.skill, context: context, executor: executor) }
    }

    // MARK: - Matching

    private func skillMatches(
        _ skill: Skill,
        contentKind: ClipboardContentKind,
        entities: [DetectedEntityType],
        sourceContext: SourceAppContext
    ) -> Bool {
        if !skill.contentTypes.isEmpty {
            guard skill.contentTypes.contains(where: { $0.matches(contentKind) }) else { return false }
        }
        if !skill.entityTypes.isEmpty {
            guard skill.entityTypes.contains(where: { $0.matchesAny(entities) }) else { return false }
        }
        if !skill.sourceContexts.isEmpty {
            guard skill.sourceContexts.contains(where: { $0.matches(sourceContext) }) else { return false }
        }
        return true
    }

    // MARK: - Conversion

    private func toSuggestedAction(
        _ skill: Skill,
        context: ClipboardContext,
        executor: ToolExecutor
    ) -> SuggestedAction {
        let subtitle = buildMatchReason(skill: skill, context: context)
        return SuggestedAction(
            skillId: skill.id,
            title: skill.description,
            subtitle: subtitle,
            systemImage: skill.icon
        ) { [weak executor] completion, onToken in
            guard let executor else { return nil }
            return executor.execute(
                skill: skill,
                context: context,
                completion: completion,
                onToken: onToken
            )
        }
    }

    private func buildMatchReason(skill: Skill, context: ClipboardContext) -> String {
        var parts: [String] = []

        let matchedEntity = skill.entityTypes.first { $0.matchesAny(context.snapshot.detectedEntities) }
        if let entity = matchedEntity {
            parts.append(entity.displayName)
        }

        let source = context.sourceAppContext
        if !skill.sourceContexts.isEmpty || (skill.parsedSourceBoosts[source] ?? 0) > 0 {
            parts.append(source.displayName)
        }

        let count = UsageHistory.shared.count(
            for: skill.id,
            contentKind: context.snapshot.kind,
            sourceContext: source
        )
        if count > 0 {
            parts.append("used \(count)×")
        }

        return parts.joined(separator: " · ")
    }

    private func relevanceScore(
        for skill: Skill,
        context: ClipboardContext,
        sourceContext: SourceAppContext
    ) -> Int {
        let textLength = context.snapshot.plainText?.count ?? 0
        let sourceBoost = skill.parsedSourceBoosts[sourceContext] ?? 0
        let entityBoost = skill.entityTypes.isEmpty ? 0 : 40
        let historyBoost = UsageHistory.shared.boost(
            for: skill.id,
            contentKind: context.snapshot.kind,
            sourceContext: sourceContext
        )

        let lengthBoost: Int
        if let min = skill.minimumCharacterCount, textLength >= min {
            lengthBoost = 30
        } else if let max = skill.maximumCharacterCount, textLength > 0, textLength <= max {
            lengthBoost = 15
        } else {
            lengthBoost = 0
        }

        let lengthPenalty: Int
        if let min = skill.minimumCharacterCount, textLength > 0, textLength < min {
            lengthPenalty = -25
        } else if let max = skill.maximumCharacterCount, textLength > max {
            lengthPenalty = -10
        } else {
            lengthPenalty = 0
        }

        return sourceBoost + entityBoost + lengthBoost + lengthPenalty + historyBoost
    }

    // MARK: - Custom Skills

    private func loadCustomSkills(into skills: inout [Skill]) {
        let customDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copycopy/skills")

        guard FileManager.default.fileExists(atPath: customDir.path) else { return }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: customDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }

            let skillFile = entry.appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }

            let id = entry.lastPathComponent
            do {
                let parsed = try SkillParser.parseAll(id: id, content: content, isBuiltIn: false)
                for skill in parsed {
                    if let existingIndex = skills.firstIndex(where: { $0.id == skill.id }) {
                        skills[existingIndex] = skill
                        Logger.info("Custom skill '\(skill.id)' overrides built-in", category: .general)
                    } else {
                        skills.append(skill)
                        Logger.info("Loaded custom skill '\(skill.id)'", category: .general)
                    }
                }
            } catch {
                Logger.error("Failed to parse custom skill '\(id)': \(error)", category: .general)
            }
        }
    }
}
