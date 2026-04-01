import Foundation

@MainActor
final class SkillLoader {
    private var skills: [Skill] = []

    init() {
        exportBuiltInSkillsIfNeeded()
        loadAll()
    }

    func loadAll() {
        var loaded: [Skill] = []

        for (id, content) in BuiltInSkills.all {
            do {
                let skill = try SkillParser.parse(id: id, content: content, isBuiltIn: true)
                loaded.append(skill)
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

        for (id, content) in BuiltInSkills.all {
            let dir = skillsDir.appendingPathComponent(id)
            let file = dir.appendingPathComponent("SKILL.md")

            do {
                let builtInSkill = try SkillParser.parse(id: id, content: content, isBuiltIn: true)
                let exportedContent = try SkillMarkdownFormatter.formatForExport(skill: builtInSkill, source: content)
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
        lhs.contentTypes == rhs.contentTypes &&
        lhs.entityTypes == rhs.entityTypes &&
        lhs.sourceContexts == rhs.sourceContexts &&
        lhs.tools == rhs.tools
    }

    func matchingActions(
        for contentKind: ClipboardContentKind,
        sourceContext: SourceAppContext,
        entity: DetectedEntityType,
        context: ClipboardContext,
        executor: ToolExecutor
    ) -> [SuggestedAction] {
        var result: [SuggestedAction] = []

        for skill in skills {
            guard skillMatches(skill, contentKind: contentKind, entity: entity, sourceContext: sourceContext) else {
                continue
            }

            for tool in skill.tools {
                guard toolMatches(tool, skill: skill, contentKind: contentKind, entity: entity, sourceContext: sourceContext) else {
                    continue
                }
                result.append(toSuggestedAction(tool, context: context, executor: executor))
            }
        }

        return result
    }

    // MARK: - Matching

    private func skillMatches(
        _ skill: Skill,
        contentKind: ClipboardContentKind,
        entity: DetectedEntityType,
        sourceContext: SourceAppContext
    ) -> Bool {
        if !skill.contentTypes.isEmpty {
            guard skill.contentTypes.contains(where: { $0.matches(contentKind) }) else { return false }
        }
        if !skill.entityTypes.isEmpty {
            guard skill.entityTypes.contains(where: { $0.matches(entity) }) else { return false }
        }
        if !skill.sourceContexts.isEmpty {
            guard skill.sourceContexts.contains(where: { $0.matches(sourceContext) }) else { return false }
        }
        return true
    }

    private func toolMatches(
        _ tool: ToolDefinition,
        skill: Skill,
        contentKind: ClipboardContentKind,
        entity: DetectedEntityType,
        sourceContext: SourceAppContext
    ) -> Bool {
        let entityTypes = tool.parsedEntityTypes
        if !entityTypes.isEmpty {
            guard entityTypes.contains(where: { $0.matches(entity) }) else { return false }
        }
        let sourceContexts = tool.parsedSourceContexts
        if !sourceContexts.isEmpty {
            guard sourceContexts.contains(where: { $0.matches(sourceContext) }) else { return false }
        }
        return true
    }

    // MARK: - Conversion

    private func toSuggestedAction(
        _ tool: ToolDefinition,
        context: ClipboardContext,
        executor: ToolExecutor
    ) -> SuggestedAction {
        let subtitle = tool.executeFunction?.displayName
        return SuggestedAction(
            title: tool.description,
            subtitle: subtitle,
            systemImage: tool.icon
        ) { [weak executor] completion in
            guard let executor else { return }
            executor.execute(tool: tool, context: context, completion: completion)
        }
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
                let skill = try SkillParser.parse(id: id, content: content, isBuiltIn: false)
                if let existingIndex = skills.firstIndex(where: { $0.id == id }) {
                    skills[existingIndex] = skill
                    Logger.info("Custom skill '\(id)' overrides built-in", category: .general)
                } else {
                    skills.append(skill)
                    Logger.info("Loaded custom skill '\(id)'", category: .general)
                }
            } catch {
                Logger.error("Failed to parse custom skill '\(id)': \(error)", category: .general)
            }
        }
    }
}
