import Foundation

@MainActor
final class SkillLoader {
    private static let orphanedGroupIDs: Set<String> = [
        "urls", "files", "images", "text", "places", "code", "transform", "filesystem",
        "contacts", "social", "tracking", "finance", "datetime", "identity"
    ]

    private var skills: [Skill] = []

    /// Maximum number of primary suggestions to surface for a single copy. Most built-in
    /// skills declare only `content-types: text`, so a generic text copy matches nearly all
    /// of them; without a cap the panel would list ~20 actions. The list is already ranked
    /// by relevance/usage before truncation, so this keeps the strongest matches only.
    static let maxPrimarySuggestions = 8

    /// Built-in skill ids that a user-provided custom skill replaced during the last load.
    /// Surfaced in Settings so the override is visible instead of only logged.
    private(set) var overriddenBuiltInIds: [String] = []

    init() {
        exportBuiltInSkillsIfNeeded()
        loadAll()
    }

    func loadAll() {
        var loaded: [Skill] = []
        overriddenBuiltInIds = []

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
        executor: ToolExecutor,
        limit: Int? = nil
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

        let sorted = ranked.sorted {
            if $0.score == $1.score {
                return $0.order < $1.order
            }
            return $0.score > $1.score
        }

        // Truncate the already-ranked list so a generic copy doesn't flood the panel.
        // Only the primary suggestion path passes a limit; follow-up matching keeps the
        // full pool so its own filter + prefix has candidates to work with.
        let capped = limit.map { Array(sorted.prefix(max(0, $0))) } ?? sorted

        return capped.map { toSuggestedAction($0.skill, context: context, executor: executor) }
    }

    // MARK: - Freeform intent routing

    /// Stopwords ignored when matching a freeform ask against skill keywords so
    /// generic filler ("the copied text") doesn't create spurious matches.
    private static let freeformStopwords: Set<String> = [
        "the", "this", "that", "these", "those", "a", "an", "to", "of", "in", "on",
        "for", "and", "or", "it", "its", "my", "your", "please", "me", "with",
        "into", "from", "as", "text", "copied", "clipboard", "content", "make", "here"
    ]

    /// Attempts to route a freeform ask to a tuned AI skill by matching the ask
    /// against each skill's `name`/`description` keywords. Conservative: only
    /// returns a skill on a strong (skill-name token) match — everything else
    /// returns `nil` so the caller falls through to the generic freeform prompt.
    func freeformSkillMatch(
        for ask: String,
        context: ClipboardContext,
        executor: ToolExecutor
    ) -> SuggestedAction? {
        let askNormalized = Self.normalizeForMatching(ask)
        let askTokens = Set(askNormalized.split(separator: " ").map(String.init))
        guard !askTokens.isEmpty else { return nil }

        var best: (skill: Skill, score: Int)?
        for skill in skills {
            // Only AI skills are sensible freeform targets — never route to a
            // function skill (Open URL, Reveal in Finder, …).
            guard let fn = skill.executeFunction, fn == .llmPrompt || fn == .summarize else { continue }

            let nameNormalized = Self.normalizeForMatching(skill.name)
            let nameTokens = nameNormalized.split(separator: " ").map(String.init)
                .filter { $0.count >= 3 && !Self.freeformStopwords.contains($0) }
            guard !nameTokens.isEmpty else { continue }

            let nameMatches = nameTokens.filter { askTokens.contains($0) }.count
            var score = nameMatches * 10
            if !nameNormalized.isEmpty, askNormalized.contains(nameNormalized) { score += 5 }

            let descTokens = Set(Self.normalizeForMatching(skill.description)
                .split(separator: " ").map(String.init)
                .filter { $0.count >= 4 && !Self.freeformStopwords.contains($0) })
            score += descTokens.intersection(askTokens).count

            if score > (best?.score ?? 0) { best = (skill, score) }
        }

        // Require at least one skill-name token in the ask (score >= 10) so only
        // strong matches redirect; weaker/description-only overlap stays generic.
        guard let match = best, match.score >= 10 else { return nil }
        return toSuggestedAction(match.skill, context: context, executor: executor)
    }

    /// Lowercases and reduces text to space-separated alphanumeric tokens.
    private static func normalizeForMatching(_ text: String) -> String {
        let mapped = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
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
                        if skills[existingIndex].isBuiltIn, !overriddenBuiltInIds.contains(skill.id) {
                            overriddenBuiltInIds.append(skill.id)
                        }
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
