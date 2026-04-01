import Foundation

enum SkillParser {
    struct ParseError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func parse(id: String, content: String, isBuiltIn: Bool) throws -> Skill {
        let (frontmatter, body) = try extractFrontmatter(content)
        let tools = try parseTools(id: id, body: body)

        guard let name = frontmatter["name"] else {
            throw ParseError(message: "Skill '\(id)' missing required 'name' field")
        }
        guard let description = frontmatter["description"] else {
            throw ParseError(message: "Skill '\(id)' missing required 'description' field")
        }

        let contentTypes = parseFilterArray(
            frontmatter["metadata.copycopy-content-types"]
                ?? frontmatter["metadata.content_types"]
                ?? frontmatter["content_types"]
        ) { ContentTypeFilter(rawValue: $0) }

        let entityTypes = parseFilterArray(
            frontmatter["metadata.copycopy-entity-types"]
                ?? frontmatter["metadata.entity_types"]
                ?? frontmatter["entity_types"]
        ) { EntityFilter(rawValue: $0) }

        let sourceContexts = parseFilterArray(
            frontmatter["metadata.copycopy-source-contexts"]
                ?? frontmatter["metadata.source_contexts"]
                ?? frontmatter["source_contexts"]
        ) { SourceContextFilter(rawValue: $0) }

        return Skill(
            id: id,
            name: name,
            description: description,
            contentTypes: contentTypes,
            entityTypes: entityTypes,
            sourceContexts: sourceContexts,
            tools: tools,
            isBuiltIn: isBuiltIn
        )
    }

    private static func extractFrontmatter(_ content: String) throws -> ([String: String], String) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw ParseError(message: "Missing opening '---' delimiter")
        }

        var frontmatter: [String: String] = [:]
        var endIndex = 0
        var currentSection: String?

        for index in 1..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" {
                endIndex = index
                break
            }

            let isIndented = line.hasPrefix("  ") || line.hasPrefix("\t")
            guard let colonRange = trimmed.range(of: ":") else { continue }

            let key = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if isIndented, let currentSection {
                frontmatter["\(currentSection).\(key)"] = value
            } else if value.isEmpty {
                currentSection = key
            } else {
                currentSection = nil
                frontmatter[key] = value
            }
        }

        guard endIndex > 0 else {
            throw ParseError(message: "Missing closing '---' delimiter")
        }

        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n")
        return (frontmatter, body)
    }

    private static func parseTools(id: String, body: String) throws -> [ToolDefinition] {
        if let jsonBlock = extractJSONBlock(afterHeading: "## Tools", in: body) {
            let data = Data(jsonBlock.utf8)
            do {
                let tools = try JSONDecoder().decode([ToolDefinition].self, from: data)
                try validateTools(tools, skillID: id)
                return tools
            } catch {
                throw ParseError(message: "Skill '\(id)' has invalid JSON tools block: \(error)")
            }
        }

        let legacyActions = parseLegacyActions(body)
        let tools = try legacyActions.map(buildLegacyToolDefinition)
        try validateTools(tools, skillID: id)
        return tools
    }

    private static func validateTools(_ tools: [ToolDefinition], skillID: String) throws {
        for tool in tools {
            _ = try ToolValidator.validateExecuteFunction(tool.execute)
            try ToolValidator.validateJSONObjectParameters(tool.parameters)
            if tool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ParseError(message: "Skill '\(skillID)' tool '\(tool.id)' is missing a name")
            }
        }
    }

    private static func extractJSONBlock(afterHeading heading: String, in body: String) -> String? {
        let lines = body.components(separatedBy: "\n")
        var sawHeading = false
        var collecting = false
        var collected: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !sawHeading {
                if trimmed == heading {
                    sawHeading = true
                }
                continue
            }

            if !collecting {
                if trimmed.hasPrefix("## "), trimmed != heading {
                    return nil
                }
                if trimmed == "```json" {
                    collecting = true
                }
                continue
            }

            if trimmed == "```" {
                return collected.joined(separator: "\n")
            }

            collected.append(line)
        }

        return nil
    }

    private static func parseLegacyActions(_ body: String) -> [LegacySkillAction] {
        let lines = body.components(separatedBy: "\n")
        var actions: [LegacySkillAction] = []
        var currentID: String?
        var currentProps: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                if let currentID, let action = buildLegacyAction(id: currentID, props: currentProps) {
                    actions.append(action)
                }
                currentID = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentProps = [:]
                continue
            }

            guard currentID != nil, let colonRange = trimmed.range(of: ":") else { continue }
            let key = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            currentProps[key] = value
        }

        if let currentID, let action = buildLegacyAction(id: currentID, props: currentProps) {
            actions.append(action)
        }

        return actions
    }

    private static func buildLegacyAction(id: String, props: [String: String]) -> LegacySkillAction? {
        guard let typeString = props["type"], let type = LegacySkillActionType(rawValue: typeString) else {
            return nil
        }
        guard let description = props["description"] else {
            return nil
        }

        return LegacySkillAction(
            id: id,
            type: type,
            icon: props["icon"] ?? "star",
            description: description,
            function: props["function"].flatMap(ActionType.init(rawValue:)),
            template: props["template"],
            prompt: props["prompt"],
            sourceContexts: parseFilterArray(props["source_contexts"]) { SourceContextFilter(rawValue: $0) },
            entityTypes: parseFilterArray(props["entity_types"]) { EntityFilter(rawValue: $0) }
        )
    }

    private static func buildLegacyToolDefinition(from action: LegacySkillAction) throws -> ToolDefinition {
        let filters = LegacyFilters(
            entityTypes: action.entityTypes.map(\.rawValue),
            sourceContexts: action.sourceContexts.map(\.rawValue)
        )

        switch action.type {
        case .prompt:
            guard let prompt = action.prompt else {
                throw ParseError(message: "Legacy action '\(action.id)' is missing a prompt")
            }
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.llmPrompt.rawValue,
                parameters: toolParameters(
                    properties: [
                        "systemPrompt": literalProperty(value: prompt, description: "System prompt"),
                        "prompt": sourcedProperty(source: "clipboard", description: "Clipboard text"),
                    ],
                    required: ["systemPrompt", "prompt"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )

        case .function:
            guard let function = action.function else {
                throw ParseError(message: "Legacy action '\(action.id)' is missing a function")
            }
            return try buildLegacyFunctionTool(action: action, function: function, filters: filters)
        }
    }

    private static func buildLegacyFunctionTool(
        action: LegacySkillAction,
        function: ActionType,
        filters: LegacyFilters
    ) throws -> ToolDefinition {
        switch function {
        case .openURL:
            return try buildLegacyOpenURLTool(action: action, filters: filters)

        case .shellCommand:
            return try buildLegacyShellTool(action: action, filters: filters)

        case .openApp:
            guard let template = action.template else {
                throw ParseError(message: "Legacy action '\(action.id)' is missing a template")
            }
            let appName = inferLegacyAppName(from: template)
            let textProperty = try textProperty(from: template, description: "Text to copy into the app")
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.openApp.rawValue,
                parameters: toolParameters(
                    properties: [
                        "appName": literalProperty(value: appName, description: "Allowlisted app name"),
                        "text": textProperty,
                    ],
                    required: ["appName"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )

        case .revealInFinder:
            return directTool(action: action, execute: .revealInFinder, filters: filters)

        case .openFile:
            return directTool(action: action, execute: .openFile, filters: filters)

        case .copyToClipboard:
            let textProperty = try textProperty(from: action.template ?? "{text}", description: "Text to copy")
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.copyToClipboard.rawValue,
                parameters: toolParameters(
                    properties: ["text": textProperty],
                    required: ["text"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )

        case .saveImage:
            return directTool(action: action, execute: .saveImage, filters: filters)

        case .saveTempFile:
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.saveTempFile.rawValue,
                parameters: toolParameters(
                    properties: ["text": sourcedProperty(source: "clipboard", description: "Clipboard text")],
                    required: ["text"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )

        case .stripANSI:
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.stripANSI.rawValue,
                parameters: toolParameters(
                    properties: ["text": sourcedProperty(source: "clipboard", description: "Clipboard text")],
                    required: ["text"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )

        case .htmlToMarkdown:
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.htmlToMarkdown.rawValue,
                parameters: toolParameters(
                    properties: ["html": sourcedProperty(source: "clipboard", description: "Clipboard HTML")],
                    required: ["html"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )

        case .summarize:
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.summarize.rawValue,
                parameters: toolParameters(
                    properties: ["text": sourcedProperty(source: "clipboard", description: "Clipboard text")],
                    required: ["text"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )
        }
    }

    private static func buildLegacyOpenURLTool(
        action: LegacySkillAction,
        filters: LegacyFilters
    ) throws -> ToolDefinition {
        let template = action.template?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "{text}"

        if template == "{text}" || template == "{TEXT}" {
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.openURL.rawValue,
                parameters: toolParameters(
                    properties: ["url": sourcedProperty(source: "clipboardURL", description: "Clipboard URL")],
                    required: ["url"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )
        }

        if !template.contains("{") {
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.openStaticURL.rawValue,
                parameters: toolParameters(
                    properties: ["url": literalProperty(value: template, description: "Static URL")],
                    required: ["url"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )
        }

        let placeholder = try extractPlaceholder(from: template)
        let property = sourcedProperty(
            source: placeholder.source,
            description: "Migrated clipboard input",
            prefix: placeholder.prefix,
            suffix: placeholder.suffix
        )

        if let queryRange = template.range(of: "?") {
            let prefix = String(template[..<queryRange.lowerBound])
            let tail = String(template[queryRange.upperBound...])
            let parts = tail.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let query = String(parts[0])
            let fragment = parts.count > 1 ? String(parts[1]) : nil

            var properties: [String: ToolProperty] = [
                "baseURL": literalProperty(value: prefix, description: "Base URL"),
            ]
            var required = ["baseURL"]

            for item in query.split(separator: "&", omittingEmptySubsequences: false) {
                let pair = String(item).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = pair.first, !name.isEmpty else { continue }
                let value = pair.count > 1 ? String(pair[1]) : ""
                if value.contains(placeholder.token) {
                    let valuePlaceholder = try extractPlaceholder(from: value)
                    properties[String(name)] = sourcedProperty(
                        source: valuePlaceholder.source,
                        description: "Migrated query parameter",
                        prefix: valuePlaceholder.prefix,
                        suffix: valuePlaceholder.suffix
                    )
                    required.append(String(name))
                } else {
                    properties[String(name)] = literalProperty(value: value, description: "Static query parameter")
                    required.append(String(name))
                }
            }

            if let fragment {
                if fragment.contains(placeholder.token) {
                    let fragmentPlaceholder = try extractPlaceholder(from: fragment)
                    properties["fragment"] = sourcedProperty(
                        source: fragmentPlaceholder.source,
                        description: "Migrated URL fragment",
                        prefix: fragmentPlaceholder.prefix,
                        suffix: fragmentPlaceholder.suffix
                    )
                    required.append("fragment")
                } else {
                    properties["fragment"] = literalProperty(value: fragment, description: "Static URL fragment")
                    required.append("fragment")
                }
            }

            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.openURLTemplate.rawValue,
                parameters: toolParameters(properties: properties, required: required),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )
        }

        if let fragmentRange = template.range(of: "#") {
            let baseURL = String(template[..<fragmentRange.lowerBound])
            let fragment = String(template[fragmentRange.upperBound...])
            let fragmentPlaceholder = try extractPlaceholder(from: fragment)
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.openURLTemplate.rawValue,
                parameters: toolParameters(
                    properties: [
                        "baseURL": literalProperty(value: baseURL, description: "Base URL"),
                        "fragment": sourcedProperty(
                            source: fragmentPlaceholder.source,
                            description: "Migrated URL fragment",
                            prefix: fragmentPlaceholder.prefix,
                            suffix: fragmentPlaceholder.suffix
                        ),
                    ],
                    required: ["baseURL", "fragment"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts
            )
        }

        let baseURL = template.replacingOccurrences(of: placeholder.token, with: "")
        return ToolDefinition(
            id: action.id,
            name: action.description,
            description: action.description,
            icon: action.icon,
            execute: ExecuteFunction.openURLTemplate.rawValue,
            parameters: toolParameters(
                properties: [
                    "baseURL": literalProperty(value: baseURL, description: "Base URL"),
                    "path": property,
                ],
                required: ["baseURL", "path"]
            ),
            entityTypes: filters.entityTypes,
            sourceContexts: filters.sourceContexts
        )
    }

    private static func buildLegacyShellTool(
        action: LegacySkillAction,
        filters: LegacyFilters
    ) throws -> ToolDefinition {
        let template = action.template?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let execute: ExecuteFunction
        let properties: [String: ToolProperty]
        let required: [String]

        switch template {
        case "echo {text} | python3 -m json.tool | pbcopy":
            execute = .formatJSON
            properties = ["json": sourcedProperty(source: "clipboard", description: "Clipboard JSON")]
            required = ["json"]

        case "echo {text} | base64 -d | pbcopy":
            execute = .decodeBase64
            properties = ["text": sourcedProperty(source: "clipboard", description: "Clipboard Base64")]
            required = ["text"]

        case "python3 -c \"import urllib.parse; print(urllib.parse.unquote('{text}'))\" | pbcopy":
            execute = .decodeURL
            properties = ["text": sourcedProperty(source: "clipboard", description: "Clipboard URL-encoded text")]
            required = ["text"]

        case "ping -c 4 {text}":
            execute = .ping
            properties = ["host": sourcedProperty(source: "clipboard", description: "Hostname or IP address")]
            required = ["host"]

        case "open -R \"{text}\"":
            execute = .revealPath
            properties = ["path": sourcedProperty(source: "clipboard", description: "Clipboard path")]
            required = ["path"]

        case "open -a Terminal \"{text}\"":
            execute = .openInTerminal
            properties = ["path": sourcedProperty(source: "clipboard", description: "Clipboard path")]
            required = ["path"]

        default:
            throw ParseError(message: "Legacy shell command '\(action.id)' cannot be migrated safely")
        }

        return ToolDefinition(
            id: action.id,
            name: action.description,
            description: action.description,
            icon: action.icon,
            execute: execute.rawValue,
            parameters: toolParameters(properties: properties, required: required),
            entityTypes: filters.entityTypes,
            sourceContexts: filters.sourceContexts
        )
    }

    private static func directTool(
        action: LegacySkillAction,
        execute: ExecuteFunction,
        filters: LegacyFilters
    ) -> ToolDefinition {
        ToolDefinition(
            id: action.id,
            name: action.description,
            description: action.description,
            icon: action.icon,
            execute: execute.rawValue,
            parameters: .empty,
            entityTypes: filters.entityTypes,
            sourceContexts: filters.sourceContexts
        )
    }

    private static func textProperty(from template: String, description: String) throws -> ToolProperty {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("{") {
            return literalProperty(value: trimmed, description: description)
        }

        let placeholder = try extractPlaceholder(from: trimmed)
        return sourcedProperty(
            source: placeholder.source,
            description: description,
            prefix: placeholder.prefix,
            suffix: placeholder.suffix
        )
    }

    private static func extractPlaceholder(from template: String) throws -> PlaceholderMatch {
        let placeholders: [(token: String, source: String)] = [
            ("{text:trimmed}", "clipboardTrimmed"),
            ("{TEXT:ENCODED}", "clipboard"),
            ("{text:encoded}", "clipboard"),
            ("{TEXT}", "clipboard"),
            ("{text}", "clipboard"),
            ("{path}", "filePaths"),
            ("{charcount}", "charCount"),
            ("{linecount}", "lineCount"),
        ]

        for placeholder in placeholders {
            guard let range = template.range(of: placeholder.token) else { continue }
            let prefix = String(template[..<range.lowerBound])
            let suffix = String(template[range.upperBound...])
            guard !prefix.contains("{"), !suffix.contains("{") else { continue }
            return PlaceholderMatch(
                token: placeholder.token,
                source: placeholder.source,
                prefix: prefix.isEmpty ? nil : prefix,
                suffix: suffix.isEmpty ? nil : suffix
            )
        }

        throw ParseError(message: "Could not safely migrate legacy template '\(template)'")
    }

    private static func inferLegacyAppName(from template: String) -> String {
        let lowercased = template.lowercased()
        if lowercased.contains("claude") { return "Claude" }
        if lowercased.contains("cursor") { return "Cursor" }
        if lowercased.contains("copilot") { return "Copilot" }
        if lowercased.contains("safari") { return "Safari" }
        return "ChatGPT"
    }

    private static func toolParameters(
        properties: [String: ToolProperty],
        required: [String]
    ) -> ToolParameters {
        ToolParameters(type: "object", properties: properties, required: required)
    }

    private static func literalProperty(
        value: String,
        description: String
    ) -> ToolProperty {
        ToolProperty(type: "string", description: description, source: "literal", value: value, prefix: nil, suffix: nil)
    }

    private static func sourcedProperty(
        source: String,
        description: String,
        prefix: String? = nil,
        suffix: String? = nil
    ) -> ToolProperty {
        ToolProperty(type: "string", description: description, source: source, value: nil, prefix: prefix, suffix: suffix)
    }

    private static func parseFilterArray<T>(_ value: String?, transform: (String) -> T?) -> [T] {
        guard let value else { return [] }
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]\"'"))
        guard !cleaned.isEmpty else { return [] }
        return cleaned
            .components(separatedBy: ",")
            .compactMap { item in
                let trimmed = item.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                return trimmed.isEmpty ? nil : transform(trimmed)
            }
    }
}

private struct LegacySkillAction {
    let id: String
    let type: LegacySkillActionType
    let icon: String
    let description: String
    let function: ActionType?
    let template: String?
    let prompt: String?
    let sourceContexts: [SourceContextFilter]
    let entityTypes: [EntityFilter]
}

private enum LegacySkillActionType: String {
    case function
    case prompt
}

private struct LegacyFilters {
    let entityTypes: [String]
    let sourceContexts: [String]
}

private struct PlaceholderMatch {
    let token: String
    let source: String
    let prefix: String?
    let suffix: String?
}
