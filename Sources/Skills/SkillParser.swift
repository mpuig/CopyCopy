import Foundation

enum SkillParser {
    struct ParseError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    // MARK: - Public API

    static func parseAll(id: String, content: String, isBuiltIn: Bool) throws -> [Skill] {
        let (frontmatter, body) = try extractFrontmatter(content)

        // 1. Explicit execute in frontmatter → current flat format (backward compat)
        if frontmatter["execute"] != nil {
            let skill = try parseFlatSkill(id: id, frontmatter: frontmatter, body: body, isBuiltIn: isBuiltIn)
            return [skill]
        }

        // 2. Old grouped format: JSON tools block or legacy ### sections
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.contains("## Tools") || trimmedBody.contains("### ") {
            let parentFilters = parseParentFilters(frontmatter)
            let tools = try parseTools(id: id, body: body)
            return tools.map { tool in
                Skill(
                    id: tool.id,
                    name: tool.name,
                    description: tool.description,
                    icon: tool.icon,
                    execute: tool.execute,
                    parameters: tool.parameters,
                    contentTypes: parentFilters.contentTypes,
                    entityTypes: mergeEntityTypes(parent: parentFilters.entityTypes, tool: tool),
                    sourceContexts: mergeSourceContexts(parent: parentFilters.sourceContexts, tool: tool),
                    sourceBoosts: tool.sourceBoosts,
                    minimumCharacterCount: tool.minimumCharacterCount,
                    maximumCharacterCount: tool.maximumCharacterCount,
                    tools: [],
                    isBuiltIn: isBuiltIn
                )
            }
        }

        // 3. New body-based format: body is tool call or LLM prompt
        let skill = try parseBodySkill(id: id, frontmatter: frontmatter, body: trimmedBody, isBuiltIn: isBuiltIn)
        return [skill]
    }

    /// Convenience for callers that expect a single skill (backward compat).
    static func parse(id: String, content: String, isBuiltIn: Bool) throws -> Skill {
        let skills = try parseAll(id: id, content: content, isBuiltIn: isBuiltIn)
        guard let first = skills.first else {
            throw ParseError(message: "Skill '\(id)' produced no actions")
        }
        return first
    }

    // MARK: - Flat Format

    private static func parseFlatSkill(
        id: String,
        frontmatter: [String: String],
        body: String,
        isBuiltIn: Bool
    ) throws -> Skill {
        guard let name = frontmatter["name"] else {
            throw ParseError(message: "Skill '\(id)' missing required 'name' field")
        }
        guard let execute = frontmatter["execute"] else {
            throw ParseError(message: "Skill '\(id)' missing required 'execute' field")
        }

        _ = try ToolValidator.validateExecuteFunction(execute)

        let icon = frontmatter["icon"] ?? "star"
        let description = frontmatter["description"]
            ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first(where: { !$0.isEmpty })
            ?? name

        let contentTypes = parseFilterArray(
            frontmatter["content-types"]
                ?? frontmatter["metadata.copycopy-content-types"]
                ?? frontmatter["metadata.content_types"]
        ) { ContentTypeFilter(rawValue: $0) }

        let entityTypes = parseFilterArray(
            frontmatter["entity-types"]
                ?? frontmatter["metadata.copycopy-entity-types"]
                ?? frontmatter["metadata.entity_types"]
        ) { EntityFilter(rawValue: $0) }

        let sourceContexts = parseFilterArray(
            frontmatter["source-contexts"]
                ?? frontmatter["metadata.copycopy-source-contexts"]
                ?? frontmatter["metadata.source_contexts"]
        ) { SourceContextFilter(rawValue: $0) }

        let sourceBoosts = parseNestedSourceBoosts(frontmatter)
        var parameters = parseNestedParameters(frontmatter)

        // For LLM execute types with text-source, build parameters from frontmatter
        let textSource = frontmatter["text-source"]
        if parameters == .empty, let executeFunc = ExecuteFunction(rawValue: execute) {
            if executeFunc == .summarize, let source = textSource {
                parameters = toolParameters(
                    properties: ["text": sourcedProperty(source: source, description: "Input text")],
                    required: ["text"]
                )
            } else if executeFunc == .llmPrompt {
                let prompt = body.trimmingCharacters(in: .whitespacesAndNewlines)
                parameters = toolParameters(
                    properties: [
                        "systemPrompt": literalProperty(value: prompt, description: "System prompt"),
                        "prompt": sourcedProperty(source: textSource ?? "clipboard", description: "Input text"),
                    ],
                    required: ["systemPrompt", "prompt"]
                )
            }
        }

        let minimumCharacterCount = (frontmatter["minimum-chars"] ?? frontmatter["minimum_characters"]).flatMap(Int.init)
        let maximumCharacterCount = (frontmatter["maximum-chars"] ?? frontmatter["maximum_characters"]).flatMap(Int.init)

        let skill = Skill(
            id: id,
            name: name,
            description: description,
            icon: icon,
            execute: execute,
            parameters: parameters,
            contentTypes: contentTypes,
            entityTypes: entityTypes,
            sourceContexts: sourceContexts,
            sourceBoosts: sourceBoosts.isEmpty ? nil : sourceBoosts,
            minimumCharacterCount: minimumCharacterCount,
            maximumCharacterCount: maximumCharacterCount,
            tools: [],
            isBuiltIn: isBuiltIn
        )

        try ToolValidator.validateJSONObjectParameters(skill.parameters)
        return skill
    }

    // MARK: - Body-Based Format

    private static func parseBodySkill(
        id: String,
        frontmatter: [String: String],
        body: String,
        isBuiltIn: Bool
    ) throws -> Skill {
        guard let name = frontmatter["name"] else {
            throw ParseError(message: "Skill '\(id)' missing required 'name' field")
        }
        guard let description = frontmatter["description"] else {
            throw ParseError(message: "Skill '\(id)' missing required 'description' field")
        }

        let icon = frontmatter["icon"] ?? "star"
        let filters = parseCommonFilters(frontmatter)
        let declaredTools = parseToolsList(frontmatter["tools"])

        // Try to parse body as a tool call: toolName(args)
        if let toolCall = parseToolCall(body) {
            let (execute, parameters) = try buildToolCallParameters(toolCall)
            return Skill(
                id: id, name: name, description: description,
                icon: icon, execute: execute, parameters: parameters,
                contentTypes: filters.contentTypes,
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts,
                sourceBoosts: filters.sourceBoosts,
                minimumCharacterCount: filters.minimumCharacterCount,
                maximumCharacterCount: filters.maximumCharacterCount,
                tools: [],
                isBuiltIn: isBuiltIn
            )
        }

        // Body is an LLM prompt — with or without tool calling
        let textSource = frontmatter["text-source"] ?? "clipboard"
        let systemPrompt = body
        let execute = declaredTools.isEmpty
            ? ExecuteFunction.llmPrompt.rawValue
            : ExecuteFunction.llmAgent.rawValue

        let parameters = toolParameters(
            properties: [
                "systemPrompt": literalProperty(value: systemPrompt, description: "System prompt"),
                "prompt": sourcedProperty(source: textSource, description: "Input text"),
            ],
            required: ["systemPrompt", "prompt"]
        )

        return Skill(
            id: id, name: name, description: description,
            icon: icon, execute: execute, parameters: parameters,
            contentTypes: filters.contentTypes,
            entityTypes: filters.entityTypes,
            sourceContexts: filters.sourceContexts,
            sourceBoosts: filters.sourceBoosts,
            minimumCharacterCount: filters.minimumCharacterCount,
            maximumCharacterCount: filters.maximumCharacterCount,
            tools: declaredTools,
            isBuiltIn: isBuiltIn
        )
    }

    private static func parseToolsList(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { ExecuteFunction(rawValue: $0) != nil }
    }

    private struct ToolCall {
        let name: String
        let argument: String
    }

    private static func parseToolCall(_ body: String) -> ToolCall? {
        let firstLine = body.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""

        guard let parenOpen = firstLine.firstIndex(of: "("),
              firstLine.hasSuffix(")") else { return nil }

        let name = String(firstLine[..<parenOpen])
        guard ExecuteFunction(rawValue: name) != nil else { return nil }

        let argStart = firstLine.index(after: parenOpen)
        let argEnd = firstLine.index(before: firstLine.endIndex)
        let argument = argStart < argEnd ? String(firstLine[argStart..<argEnd]) : ""

        return ToolCall(name: name, argument: argument)
    }

    /// Map from ExecuteFunction to the parameter name ToolExecutor expects.
    private static let toolParameterNames: [String: String] = [
        "openURL": "url",
        "formatJSON": "json",
        "decodeBase64": "text",
        "decodeURL": "text",
        "stripANSI": "text",
        "htmlToMarkdown": "html",
        "copyToClipboard": "text",
        "saveTempFile": "text",
        "revealPath": "path",
        "openInTerminal": "path",
        "ping": "host",
    ]

    private static func buildToolCallParameters(_ call: ToolCall) throws -> (execute: String, parameters: ToolParameters) {
        // No-arg tools
        if call.argument.isEmpty {
            return (call.name, .empty)
        }

        let template = call.argument

        // openURL with a full URL template (contains ? or literal URL parts)
        if call.name == "openURL" || call.name == "openURLTemplate" {
            return try buildURLToolParameters(template)
        }

        // Single-arg tools: extract placeholder from template
        guard let paramName = toolParameterNames[call.name] else {
            throw ParseError(message: "Unknown tool '\(call.name)' or missing parameter mapping")
        }

        let placeholder = try extractPlaceholder(from: template)
        let property = sourcedProperty(
            source: placeholder.source,
            description: paramName,
            prefix: placeholder.prefix,
            suffix: placeholder.suffix
        )
        return (call.name, toolParameters(properties: [paramName: property], required: [paramName]))
    }

    private static func buildURLToolParameters(_ template: String) throws -> (execute: String, parameters: ToolParameters) {
        // Simple clipboard URL: openURL({clipboard}) or openURL({clipboardURL})
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        if trimmed == "{clipboard}" || trimmed == "{clipboardURL}" || trimmed == "{clipboardTrimmed}" {
            let placeholder = try extractPlaceholder(from: trimmed)
            return (
                ExecuteFunction.openURL.rawValue,
                toolParameters(
                    properties: ["url": sourcedProperty(source: placeholder.source, description: "URL")],
                    required: ["url"]
                )
            )
        }

        // Static URL (no placeholders)
        if !trimmed.contains("{") {
            return (
                ExecuteFunction.openStaticURL.rawValue,
                toolParameters(
                    properties: ["url": literalProperty(value: trimmed, description: "URL")],
                    required: ["url"]
                )
            )
        }

        // URL template with query params: https://example.com/?q={clipboard}
        if let queryRange = trimmed.range(of: "?") {
            let baseURL = String(trimmed[..<queryRange.lowerBound])
            let query = String(trimmed[queryRange.upperBound...])

            var properties: [String: ToolProperty] = [
                "baseURL": literalProperty(value: baseURL, description: "Base URL"),
            ]
            var required = ["baseURL"]

            for item in query.split(separator: "&", omittingEmptySubsequences: false) {
                let pair = String(item).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = pair.first, !name.isEmpty else { continue }
                let value = pair.count > 1 ? String(pair[1]) : ""
                if value.contains("{") {
                    let p = try extractPlaceholder(from: value)
                    properties[String(name)] = sourcedProperty(source: p.source, description: String(name), prefix: p.prefix, suffix: p.suffix)
                } else {
                    properties[String(name)] = literalProperty(value: value, description: String(name))
                }
                required.append(String(name))
            }

            return (ExecuteFunction.openURLTemplate.rawValue, toolParameters(properties: properties, required: required))
        }

        // URL template with path: maps://{clipboard} or https://github.com/{clipboard}
        let placeholder = try extractPlaceholder(from: trimmed)
        let baseURL = trimmed.replacingOccurrences(of: placeholder.token, with: "")
        return (
            ExecuteFunction.openURLTemplate.rawValue,
            toolParameters(
                properties: [
                    "baseURL": literalProperty(value: baseURL, description: "Base URL"),
                    "path": sourcedProperty(source: placeholder.source, description: "Path", prefix: placeholder.prefix, suffix: placeholder.suffix),
                ],
                required: ["baseURL", "path"]
            )
        )
    }

    private struct CommonFilters {
        let contentTypes: [ContentTypeFilter]
        let entityTypes: [EntityFilter]
        let sourceContexts: [SourceContextFilter]
        let sourceBoosts: [String: Int]?
        let minimumCharacterCount: Int?
        let maximumCharacterCount: Int?
    }

    private static func parseCommonFilters(_ frontmatter: [String: String]) -> CommonFilters {
        CommonFilters(
            contentTypes: parseFilterArray(
                frontmatter["content-types"] ?? frontmatter["metadata.copycopy-content-types"] ?? frontmatter["metadata.content_types"]
            ) { ContentTypeFilter(rawValue: $0) },
            entityTypes: parseFilterArray(
                frontmatter["entity-types"] ?? frontmatter["metadata.copycopy-entity-types"] ?? frontmatter["metadata.entity_types"]
            ) { EntityFilter(rawValue: $0) },
            sourceContexts: parseFilterArray(
                frontmatter["source-contexts"] ?? frontmatter["metadata.copycopy-source-contexts"] ?? frontmatter["metadata.source_contexts"]
            ) { SourceContextFilter(rawValue: $0) },
            sourceBoosts: {
                let boosts = parseNestedSourceBoosts(frontmatter)
                return boosts.isEmpty ? nil : boosts
            }(),
            minimumCharacterCount: (frontmatter["minimum-chars"] ?? frontmatter["minimum_characters"]).flatMap(Int.init),
            maximumCharacterCount: (frontmatter["maximum-chars"] ?? frontmatter["maximum_characters"]).flatMap(Int.init)
        )
    }

    private static func parseNestedSourceBoosts(_ frontmatter: [String: String]) -> [String: Int] {
        var boosts: [String: Int] = [:]
        let prefix = "source-boosts."
        for (key, value) in frontmatter where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            if let intValue = Int(value) {
                boosts[name] = intValue
            }
        }
        return boosts
    }

    private static func parseNestedParameters(_ frontmatter: [String: String]) -> ToolParameters {
        // Collect parameters.{name}.{field} entries
        let prefix = "parameters."
        var paramsByName: [String: [String: String]] = [:]

        for (key, value) in frontmatter where key.hasPrefix(prefix) {
            let rest = String(key.dropFirst(prefix.count))
            let parts = rest.split(separator: ".", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let paramName = String(parts[0])
            let field = String(parts[1])
            paramsByName[paramName, default: [:]][field] = value
        }

        guard !paramsByName.isEmpty else { return .empty }

        var properties: [String: ToolProperty] = [:]
        var required: [String] = []

        for (name, fields) in paramsByName.sorted(by: { $0.key < $1.key }) {
            properties[name] = ToolProperty(
                type: "string",
                description: fields["description"] ?? name,
                source: fields["source"],
                value: fields["value"],
                prefix: fields["prefix"],
                suffix: fields["suffix"]
            )
            required.append(name)
        }

        return ToolParameters(type: "object", properties: properties, required: required)
    }

    // MARK: - Grouped Format (backward compat)

    private struct ParentFilters {
        let contentTypes: [ContentTypeFilter]
        let entityTypes: [EntityFilter]
        let sourceContexts: [SourceContextFilter]
    }

    private static func parseParentFilters(_ frontmatter: [String: String]) -> ParentFilters {
        ParentFilters(
            contentTypes: parseFilterArray(
                frontmatter["metadata.copycopy-content-types"]
                    ?? frontmatter["metadata.content_types"]
                    ?? frontmatter["content_types"]
            ) { ContentTypeFilter(rawValue: $0) },
            entityTypes: parseFilterArray(
                frontmatter["metadata.copycopy-entity-types"]
                    ?? frontmatter["metadata.entity_types"]
                    ?? frontmatter["entity_types"]
            ) { EntityFilter(rawValue: $0) },
            sourceContexts: parseFilterArray(
                frontmatter["metadata.copycopy-source-contexts"]
                    ?? frontmatter["metadata.source_contexts"]
                    ?? frontmatter["source_contexts"]
            ) { SourceContextFilter(rawValue: $0) }
        )
    }

    private static func mergeEntityTypes(parent: [EntityFilter], tool: ToolDefinition) -> [EntityFilter] {
        let toolTypes = tool.parsedEntityTypes
        return toolTypes.isEmpty ? parent : toolTypes
    }

    private static func mergeSourceContexts(parent: [SourceContextFilter], tool: ToolDefinition) -> [SourceContextFilter] {
        let toolContexts = tool.parsedSourceContexts
        return toolContexts.isEmpty ? parent : toolContexts
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

    // MARK: - Frontmatter Extraction

    private static func extractFrontmatter(_ content: String) throws -> ([String: String], String) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw ParseError(message: "Missing opening '---' delimiter")
        }

        var frontmatter: [String: String] = [:]
        var endIndex = 0
        var sectionStack: [String] = []

        for index in 1..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" {
                endIndex = index
                break
            }

            let indentLevel = countIndentLevel(line)
            guard let colonRange = trimmed.range(of: ":") else { continue }

            let key = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            // Adjust section stack based on indent
            while sectionStack.count > indentLevel {
                sectionStack.removeLast()
            }

            if value.isEmpty {
                // Section header
                if indentLevel == 0 {
                    sectionStack = [key]
                } else {
                    sectionStack.append(key)
                }
            } else {
                let cleanedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if sectionStack.isEmpty {
                    frontmatter[key] = cleanedValue
                } else {
                    let fullKey = (sectionStack + [key]).joined(separator: ".")
                    frontmatter[fullKey] = cleanedValue
                }
            }
        }

        guard endIndex > 0 else {
            throw ParseError(message: "Missing closing '---' delimiter")
        }

        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n")
        return (frontmatter, body)
    }

    private static func countIndentLevel(_ line: String) -> Int {
        var spaces = 0
        for char in line {
            if char == " " { spaces += 1 }
            else if char == "\t" { spaces += 2 }
            else { break }
        }
        return spaces / 2
    }

    // MARK: - JSON Block Extraction

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

    // MARK: - Legacy Format Parsing

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
            textSource: props["text_source"],
            sourceContexts: parseFilterArray(props["source_contexts"]) { SourceContextFilter(rawValue: $0) },
            entityTypes: parseFilterArray(props["entity_types"]) { EntityFilter(rawValue: $0) },
            sourceBoosts: parseSourceBoosts(props["source_boosts"]),
            minimumCharacterCount: props["minimum_characters"].flatMap(Int.init),
            maximumCharacterCount: props["maximum_characters"].flatMap(Int.init)
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
                        "prompt": sourcedProperty(
                            source: action.textSource ?? "clipboardChatCleaned",
                            description: "Clipboard text"
                        ),
                    ],
                    required: ["systemPrompt", "prompt"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                    properties: ["text": sourcedProperty(source: "clipboardLLM", description: "Clipboard text")],
                    required: ["text"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
            )

        case .htmlToMarkdown:
            return ToolDefinition(
                id: action.id,
                name: action.description,
                description: action.description,
                icon: action.icon,
                execute: ExecuteFunction.htmlToMarkdown.rawValue,
                parameters: toolParameters(
                    properties: ["html": sourcedProperty(source: "clipboardHTML", description: "Clipboard HTML")],
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
                    properties: [
                        "text": sourcedProperty(
                            source: action.textSource ?? "clipboardChatCleaned",
                            description: "Clipboard text"
                        )
                    ],
                    required: ["text"]
                ),
                entityTypes: filters.entityTypes,
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
                sourceContexts: filters.sourceContexts,
                sourceBoosts: action.sourceBoosts,
                minimumCharacterCount: action.minimumCharacterCount,
                maximumCharacterCount: action.maximumCharacterCount
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
            sourceContexts: filters.sourceContexts,
            sourceBoosts: action.sourceBoosts,
            minimumCharacterCount: action.minimumCharacterCount,
            maximumCharacterCount: action.maximumCharacterCount
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
            sourceContexts: filters.sourceContexts,
            sourceBoosts: action.sourceBoosts,
            minimumCharacterCount: action.minimumCharacterCount,
            maximumCharacterCount: action.maximumCharacterCount
        )
    }

    // MARK: - Helpers

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
            sourceContexts: filters.sourceContexts,
            sourceBoosts: action.sourceBoosts,
            minimumCharacterCount: action.minimumCharacterCount,
            maximumCharacterCount: action.maximumCharacterCount
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
            // New body-based format: {sourceName} maps directly
            ("{clipboard}", "clipboard"),
            ("{clipboardURL}", "clipboardURL"),
            ("{clipboardHTML}", "clipboardHTML"),
            ("{clipboardLLM}", "clipboardLLM"),
            ("{clipboardChatCleaned}", "clipboardChatCleaned"),
            ("{clipboardClean}", "clipboardClean"),
            ("{clipboardTrimmed}", "clipboardTrimmed"),
            ("{clipboardUppercase}", "clipboardUppercase"),
            ("{clipboardLowercase}", "clipboardLowercase"),
            ("{clipboardTitleCase}", "clipboardTitleCase"),
            ("{clipboardSentenceCase}", "clipboardSentenceCase"),
            ("{filePaths}", "filePaths"),
            ("{charCount}", "charCount"),
            ("{lineCount}", "lineCount"),
            // Legacy format: {text:modifier} style
            ("{text:clean}", "clipboardClean"),
            ("{text:uppercase}", "clipboardUppercase"),
            ("{text:lowercase}", "clipboardLowercase"),
            ("{text:titlecase}", "clipboardTitleCase"),
            ("{text:sentencecase}", "clipboardSentenceCase"),
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

    static func parseFilterArray<T>(_ value: String?, transform: (String) -> T?) -> [T] {
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

    private static func parseSourceBoosts(_ value: String?) -> [String: Int] {
        guard let value else { return [:] }
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !cleaned.isEmpty else { return [:] }

        var boosts: [String: Int] = [:]
        for item in cleaned.components(separatedBy: ",") {
            let pair = item.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard pair.count == 2 else { continue }
            let key = String(pair[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(pair[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, let intValue = Int(value) else { continue }
            boosts[key] = intValue
        }
        return boosts
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
    let textSource: String?
    let sourceContexts: [SourceContextFilter]
    let entityTypes: [EntityFilter]
    let sourceBoosts: [String: Int]
    let minimumCharacterCount: Int?
    let maximumCharacterCount: Int?
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
