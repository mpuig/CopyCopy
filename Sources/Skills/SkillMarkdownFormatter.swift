import Foundation

enum SkillMarkdownFormatter {
    struct FormatError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func formatForExport(skill: Skill, source: String) throws -> String {
        let (frontmatter, body) = try extractFrontmatter(source)
        let compatibility = frontmatter["compatibility"]
        let (title, intro) = extractTitleAndIntro(from: body)

        var lines: [String] = [
            "---",
            "name: \(skill.name)",
            "description: \(skill.description)",
        ]

        if let compatibility {
            lines.append("compatibility: \(compatibility)")
        }

        let metadataLines = exportMetadata(skill: skill)
        if !metadataLines.isEmpty {
            lines.append("metadata:")
            lines.append(contentsOf: metadataLines)
        }

        lines.append("---")
        lines.append("")
        lines.append(title ?? "# \(skill.name.capitalized)")
        lines.append("")

        if let intro, !intro.isEmpty {
            lines.append(intro)
            lines.append("")
        }

        lines.append("## Actions")
        lines.append("")

        for (index, tool) in skill.tools.enumerated() {
            lines.append(contentsOf: try exportLegacyAction(tool))
            if index < skill.tools.count - 1 {
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func exportMetadata(skill: Skill) -> [String] {
        var lines: [String] = []

        if !skill.contentTypes.isEmpty {
            lines.append("  content_types: [ \(skill.contentTypes.map(\.rawValue).joined(separator: ", ")) ]")
        }
        if !skill.entityTypes.isEmpty {
            lines.append("  entity_types: [ \(skill.entityTypes.map(\.rawValue).joined(separator: ", ")) ]")
        }
        if !skill.sourceContexts.isEmpty {
            lines.append("  source_contexts: [ \(skill.sourceContexts.map(\.rawValue).joined(separator: ", ")) ]")
        }

        return lines
    }

    private static func exportLegacyAction(_ tool: ToolDefinition) throws -> [String] {
        guard let execute = tool.executeFunction else {
            throw FormatError(message: "Unsupported execute function '\(tool.execute)' for tool '\(tool.id)'")
        }

        var lines = [
            "### \(tool.id)",
            "",
        ]

        switch execute {
        case .llmPrompt:
            lines.append("type: prompt")
            lines.append("prompt: \(tool.parameters.properties["systemPrompt"]?.value ?? "")")

        case .formatJSON:
            lines.append("type: function")
            lines.append("function: shellCommand")
            lines.append("template: echo {text} | python3 -m json.tool | pbcopy")

        case .decodeBase64:
            lines.append("type: function")
            lines.append("function: shellCommand")
            lines.append("template: echo {text} | base64 -d | pbcopy")

        case .decodeURL:
            lines.append("type: function")
            lines.append("function: shellCommand")
            lines.append("template: python3 -c \"import urllib.parse; print(urllib.parse.unquote('{text}'))\" | pbcopy")

        case .ping:
            lines.append("type: function")
            lines.append("function: shellCommand")
            lines.append("template: ping -c 4 {text}")

        case .revealPath:
            lines.append("type: function")
            lines.append("function: shellCommand")
            lines.append("template: open -R \"{text}\"")

        case .openInTerminal:
            lines.append("type: function")
            lines.append("function: shellCommand")
            lines.append("template: open -a Terminal \"{text}\"")

        case .openURL:
            lines.append("type: function")
            lines.append("function: openURL")
            lines.append("template: {text}")

        case .openURLTemplate:
            lines.append("type: function")
            lines.append("function: openURL")
            lines.append("template: \(try exportURLTemplate(tool.parameters))")

        case .openStaticURL:
            lines.append("type: function")
            lines.append("function: openURL")
            lines.append("template: \(tool.parameters.properties["url"]?.value ?? "")")

        case .openApp:
            lines.append("type: function")
            lines.append("function: openApp")
            lines.append("template: \(exportTextTemplate(tool.parameters.properties["text"], encoded: false))")

        case .copyToClipboard:
            lines.append("type: function")
            lines.append("function: copyToClipboard")
            lines.append("template: \(exportTextTemplate(tool.parameters.properties["text"], encoded: false))")

        case .revealInFinder:
            lines.append("type: function")
            lines.append("function: revealInFinder")

        case .openFile:
            lines.append("type: function")
            lines.append("function: openFile")

        case .saveImage:
            lines.append("type: function")
            lines.append("function: saveImage")

        case .saveTempFile:
            lines.append("type: function")
            lines.append("function: saveTempFile")

        case .stripANSI:
            lines.append("type: function")
            lines.append("function: stripANSI")

        case .htmlToMarkdown:
            lines.append("type: function")
            lines.append("function: htmlToMarkdown")

        case .summarize:
            lines.append("type: function")
            lines.append("function: summarize")
        }

        lines.append("icon: \(tool.icon)")
        lines.append("description: \(tool.description)")

        if let entityTypes = tool.entityTypes, !entityTypes.isEmpty {
            lines.append("entity_types: [\(entityTypes.joined(separator: ", "))]")
        }
        if let sourceContexts = tool.sourceContexts, !sourceContexts.isEmpty {
            lines.append("source_contexts: [\(sourceContexts.joined(separator: ", "))]")
        }

        return lines
    }

    private static func exportURLTemplate(_ parameters: ToolParameters) throws -> String {
        if let url = parameters.properties["url"]?.value {
            return url
        }

        let baseURL = parameters.properties["baseURL"]?.value ?? ""
        let path = parameters.properties["path"]
        let fragment = parameters.properties["fragment"]

        let queryParts = parameters.properties
            .filter { !["baseURL", "path", "fragment"].contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(exportTextTemplate(value, encoded: true))"
            }

        var template = baseURL

        if let path {
            template += exportTextTemplate(path, encoded: shouldEncodePath(baseURL: baseURL))
        }

        if !queryParts.isEmpty {
            template += "?" + queryParts.joined(separator: "&")
        }

        if let fragment {
            template += "#" + exportTextTemplate(fragment, encoded: true)
        }

        if template.isEmpty {
            throw FormatError(message: "Could not export URL template")
        }

        return template
    }

    private static func shouldEncodePath(baseURL: String) -> Bool {
        baseURL.hasPrefix("dict://") || baseURL.hasPrefix("x-web-search://") || baseURL.hasSuffix("#")
    }

    private static func exportTextTemplate(_ property: ToolProperty?, encoded: Bool) -> String {
        guard let property else { return "{text}" }

        let token: String
        switch property.source {
        case nil, "literal":
            token = property.value ?? ""
        case "clipboard", "clipboardURL":
            token = encoded ? "{text:encoded}" : "{text}"
        case "clipboardTrimmed":
            token = encoded ? "{text:encoded}" : "{text:trimmed}"
        case "filePaths":
            token = "{path}"
        case "charCount":
            token = "{charcount}"
        case "lineCount":
            token = "{linecount}"
        default:
            token = "{text}"
        }

        return (property.prefix ?? "") + token + (property.suffix ?? "")
    }

    private static func extractFrontmatter(_ content: String) throws -> ([String: String], String) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw FormatError(message: "Missing opening frontmatter delimiter")
        }

        var frontmatter: [String: String] = [:]
        var currentSection: String?
        var endIndex = 0

        for index in 1..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" {
                endIndex = index
                break
            }

            let isIndented = line.hasPrefix("  ") || line.hasPrefix("\t")
            guard let colon = trimmed.range(of: ":") else { continue }

            let key = String(trimmed[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if isIndented, let currentSection {
                frontmatter["\(currentSection).\(key)"] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if value.isEmpty {
                currentSection = key
            } else {
                currentSection = nil
                frontmatter[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        guard endIndex > 0 else {
            throw FormatError(message: "Missing closing frontmatter delimiter")
        }

        return (frontmatter, lines.dropFirst(endIndex + 1).joined(separator: "\n"))
    }

    private static func extractTitleAndIntro(from body: String) -> (String?, String?) {
        let lines = body.components(separatedBy: "\n")
        var title: String?
        var introLines: [String] = []
        var afterTitle = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if title == nil, trimmed.hasPrefix("# ") {
                title = trimmed
                afterTitle = true
                continue
            }

            if afterTitle, trimmed == "## Tools" || trimmed == "## Actions" {
                break
            }

            if afterTitle {
                introLines.append(line)
            }
        }

        let intro = introLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, intro.isEmpty ? nil : intro)
    }
}
