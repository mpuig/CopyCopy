import Foundation

enum SkillMarkdownFormatter {
    static func formatFlat(skill: Skill) -> String {
        var lines: [String] = ["---"]
        lines.append("name: \(skill.name)")
        lines.append("description: \(skill.description)")
        lines.append("icon: \(skill.icon)")

        // Only emit execute: for the special summarize path
        if skill.execute == ExecuteFunction.summarize.rawValue {
            lines.append("execute: summarize")
        }

        if !skill.contentTypes.isEmpty {
            lines.append("content-types: \(skill.contentTypes.map(\.rawValue).joined(separator: ", "))")
        }
        if !skill.entityTypes.isEmpty {
            lines.append("entity-types: \(skill.entityTypes.map(\.rawValue).joined(separator: ", "))")
        }
        if !skill.sourceContexts.isEmpty {
            lines.append("source-contexts: \(skill.sourceContexts.map(\.rawValue).joined(separator: ", "))")
        }

        // For LLM prompts/agents, emit text-source if not default
        if skill.execute == ExecuteFunction.llmPrompt.rawValue || skill.execute == ExecuteFunction.summarize.rawValue || skill.execute == ExecuteFunction.llmAgent.rawValue {
            let textSource = extractTextSource(from: skill)
            if let textSource, textSource != "clipboard" {
                lines.append("text-source: \(textSource)")
            }
        }

        if !skill.tools.isEmpty {
            lines.append("tools: \(skill.tools.joined(separator: ", "))")
        }

        if let min = skill.minimumCharacterCount {
            lines.append("minimum-chars: \(min)")
        }
        if let max = skill.maximumCharacterCount {
            lines.append("maximum-chars: \(max)")
        }
        if let temp = skill.temperature {
            lines.append("temperature: \(temp)")
        }
        if let boosts = skill.sourceBoosts, !boosts.isEmpty {
            lines.append("source-boosts:")
            for (key, value) in boosts.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key): \(value)")
            }
        }

        lines.append("---")
        lines.append("")

        // Body: tool call for function skills, prompt text for LLM skills
        if skill.execute == ExecuteFunction.llmPrompt.rawValue || skill.execute == ExecuteFunction.llmAgent.rawValue {
            lines.append(extractSystemPrompt(from: skill))
        } else if skill.execute == ExecuteFunction.summarize.rawValue {
            lines.append(skill.description)
        } else {
            lines.append(buildToolCallBody(skill: skill))
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func extractTextSource(from skill: Skill) -> String? {
        if skill.execute == ExecuteFunction.llmPrompt.rawValue || skill.execute == ExecuteFunction.llmAgent.rawValue {
            return skill.parameters.properties["prompt"]?.source
        }
        if skill.execute == ExecuteFunction.summarize.rawValue {
            return skill.parameters.properties["text"]?.source
        }
        return nil
    }

    private static func extractSystemPrompt(from skill: Skill) -> String {
        skill.parameters.properties["systemPrompt"]?.value ?? skill.description
    }

    private static func buildToolCallBody(skill: Skill) -> String {
        guard let function = skill.executeFunction else {
            return "\(skill.execute)()"
        }

        switch function {
        case .openFile, .revealInFinder, .saveImage:
            return "\(skill.execute)()"

        case .openURL:
            let source = skill.parameters.properties["url"]?.source ?? "clipboard"
            return "openURL({\(source)})"

        case .openStaticURL:
            let url = skill.parameters.properties["url"]?.value ?? ""
            return "openURL(\(url))"

        case .openURLTemplate:
            return buildURLTemplateCall(skill: skill)

        default:
            // Single-arg tools: find the main parameter and its source
            let paramName = mainParameterName(for: function)
            if let prop = skill.parameters.properties[paramName] {
                let placeholder = exportPlaceholder(prop)
                return "\(skill.execute)(\(placeholder))"
            }
            return "\(skill.execute)()"
        }
    }

    private static func buildURLTemplateCall(skill: Skill) -> String {
        let baseURL = skill.parameters.properties["baseURL"]?.value ?? ""
        let path = skill.parameters.properties["path"]
        let queryParams = skill.parameters.properties
            .filter { !["baseURL", "path", "fragment"].contains($0.key) && !$0.key.hasPrefix("__copycopy_") }
            .sorted { $0.key < $1.key }

        var url = baseURL

        if let path {
            url += exportPlaceholder(path)
        }

        if !queryParams.isEmpty {
            url += "?" + queryParams.map { key, prop in
                "\(key)=\(exportPlaceholder(prop))"
            }.joined(separator: "&")
        }

        if let fragment = skill.parameters.properties["fragment"] {
            url += "#\(exportPlaceholder(fragment))"
        }

        return "openURL(\(url))"
    }

    private static func exportPlaceholder(_ prop: ToolProperty) -> String {
        if prop.source == "literal" || prop.source == nil {
            return prop.value ?? ""
        }

        let sourceToPlaceholder: [String: String] = [
            "clipboard": "clipboard",
            "clipboardURL": "clipboardURL",
            "clipboardTrimmed": "clipboardTrimmed",
            "clipboardUppercase": "clipboardUppercase",
            "clipboardLowercase": "clipboardLowercase",
            "clipboardTitleCase": "clipboardTitleCase",
            "clipboardSentenceCase": "clipboardSentenceCase",
            "clipboardHTML": "clipboardHTML",
            "clipboardLLM": "clipboardLLM",
            "clipboardChatCleaned": "clipboardChatCleaned",
            "clipboardClean": "clipboardClean",
            "filePaths": "filePaths",
        ]

        let name = sourceToPlaceholder[prop.source ?? "clipboard"] ?? "clipboard"
        let token = "{\(name)}"
        return (prop.prefix ?? "") + token + (prop.suffix ?? "")
    }

    private static func mainParameterName(for function: ExecuteFunction) -> String {
        switch function {
        case .formatJSON: return "json"
        case .htmlToMarkdown: return "html"
        case .revealPath, .openInTerminal: return "path"
        case .ping: return "host"
        case .openURL, .openStaticURL: return "url"
        default: return "text"
        }
    }
}
