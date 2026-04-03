import Cocoa
import os

@MainActor
final class ToolExecutor {
    typealias ActionCompletion = (_ text: String, _ isInClipboard: Bool) -> Void

    private let reservedURLKeys: Set<String> = ["baseURL", "path", "fragment"]
    private let internalParameterPrefix = "__copycopy_"
    private let timestampRegex = try! NSRegularExpression(
        pattern: #"\b\d{1,2}:\d{2}\s*(AM|PM)\b"#,
        options: [.caseInsensitive]
    )

    typealias StreamCallback = (_ token: String) -> Void
    typealias StatusCallback = (_ status: String) -> Void

    @discardableResult
    func execute(
        skill: Skill,
        context: ClipboardContext,
        completion: @escaping ActionCompletion,
        onToken: @escaping StreamCallback = { _ in },
        onStatus: @escaping StatusCallback = { _ in }
    ) -> (() -> Void)? {
        do {
            let function = try ToolValidator.validateExecuteFunction(skill.execute)
            try ToolValidator.validateJSONObjectParameters(skill.parameters)
            let parameters = try resolveParameters(skill.parameters, context: context)
            return execute(function: function, parameters: parameters, context: context, completion: completion, onToken: onToken, onStatus: onStatus, tools: skill.tools)
        } catch {
            Logger.error("Tool execution failed for '\(skill.id)': \(error)", category: .actions)
            completion("Failed: \(error.localizedDescription)", false)
            return nil
        }
    }

    @discardableResult
    private func execute(
        function: ExecuteFunction,
        parameters: [String: String],
        context: ClipboardContext,
        completion: @escaping ActionCompletion,
        onToken: @escaping StreamCallback = { _ in },
        onStatus: @escaping StatusCallback = { _ in },
        tools: [String] = []
    ) -> (() -> Void)? {
        do {
            switch function {
            case .openURL:
                let urlString = try requiredText(parameters["url"] ?? primaryText(from: context))
                let url = try ToolValidator.validateOpenableURL(urlString)
                NSWorkspace.shared.open(url)
                completion("Opened URL", false)

            case .openURLTemplate:
                let url = try buildTemplateURL(from: parameters)
                NSWorkspace.shared.open(url)
                completion("Opened URL", false)

            case .openApp:
                try executeOpenApp(parameters: parameters, completion: completion)

            case .openFile:
                guard let url = context.snapshot.fileURLs?.first else {
                    throw ToolExecutionError.missingFile
                }
                NSWorkspace.shared.open(url)
                completion("Opened file", false)

            case .revealInFinder:
                guard let urls = context.snapshot.fileURLs, !urls.isEmpty else {
                    throw ToolExecutionError.missingFile
                }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                completion("Revealed in Finder", false)

            case .saveImage:
                executeSaveImage(completion: completion)

            case .saveTempFile:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                executeSaveTempFile(text, completion: completion)

            case .copyToClipboard:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                copyToClipboard(text)
                completion(text, true)

            case .formatJSON:
                let json = try requiredText(parameters["json"] ?? primaryText(from: context))
                let formatted = try formatJSON(json)
                copyToClipboard(formatted)
                completion(formatted, true)

            case .decodeBase64:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                let decoded = try decodeBase64(text)
                copyToClipboard(decoded)
                completion(decoded, true)

            case .decodeURL:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                guard let decoded = text.removingPercentEncoding else {
                    throw ToolExecutionError.couldNotDecodeURL(text)
                }
                copyToClipboard(decoded)
                completion(decoded, true)

            case .stripANSI:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                let stripped = stripANSI(text)
                copyToClipboard(stripped)
                completion(stripped, true)

            case .htmlToMarkdown:
                let html = try requiredText(parameters["html"] ?? primaryHTML(from: context) ?? primaryText(from: context))
                executeHTMLToMarkdown(html, completion: completion)

            case .revealPath:
                let path = try requiredText(parameters["path"] ?? primaryText(from: context))
                let url = try ToolValidator.resolveExistingPath(path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                completion("Revealed in Finder", false)

            case .openInTerminal:
                let path = try requiredText(parameters["path"] ?? primaryText(from: context))
                let url = try ToolValidator.resolveExistingPath(path)
                try executeOpenInTerminal(url: url, completion: completion)

            case .ping:
                let host = try ToolValidator.validateHostname(
                    try requiredText(parameters["host"] ?? primaryText(from: context))
                )
                executePing(host: host, completion: completion)

            case .llmPrompt:
                let prompt = try requiredText(parameters["prompt"] ?? primaryText(from: context))
                let systemPrompt = parameters["systemPrompt"] ?? "You are a helpful assistant."
                return executeLLMPrompt(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    promptSource: sourceMetadata(named: "prompt", parameters: parameters),
                    context: context,
                    completion: completion,
                    onToken: onToken,
                    onStatus: onStatus
                )

            case .llmAgent:
                let prompt = try requiredText(parameters["prompt"] ?? primaryText(from: context))
                let systemPrompt = parameters["systemPrompt"] ?? "You are a helpful assistant."
                return executeLLMAgent(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    promptSource: sourceMetadata(named: "prompt", parameters: parameters),
                    context: context,
                    completion: completion,
                    onToken: onToken,
                    onStatus: onStatus
                )

            case .summarize:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                return executeSummarize(
                    text: text,
                    textSource: sourceMetadata(named: "text", parameters: parameters),
                    context: context,
                    completion: completion,
                    onToken: onToken,
                    onStatus: onStatus
                )

            case .openStaticURL:
                guard let urlString = parameters["url"] else {
                    throw ToolExecutionError.missingParameter("url")
                }
                let url = try ToolValidator.validateOpenableURL(urlString)
                NSWorkspace.shared.open(url)
                completion("Opened URL", false)
            }
            return nil
        } catch {
            Logger.error("Tool function \(function.rawValue) failed: \(error)", category: .actions)
            completion("Failed: \(error.localizedDescription)", false)
            return nil
        }
    }

    private func resolveParameters(
        _ parameters: ToolParameters,
        context: ClipboardContext
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]

        for (name, property) in parameters.properties {
            if let value = try resolveProperty(named: name, property: property, context: context) {
                resolved[name] = value
                if let source = property.source {
                    resolved[sourceMetadataKey(for: name)] = source
                }
            }
        }

        for key in parameters.required where resolved[key] == nil {
            throw ToolExecutionError.missingParameter(key)
        }

        return resolved
    }

    private func resolveProperty(
        named name: String,
        property: ToolProperty,
        context: ClipboardContext
    ) throws -> String? {
        let rawValue: String?

        switch property.source {
        case nil, "literal":
            rawValue = property.value
        case "clipboard":
            rawValue = primaryText(from: context)
        case "clipboardLLM":
            rawValue = bestLLMText(from: context)
        case "clipboardChatCleaned":
            rawValue = primaryText(from: context) ?? bestLLMText(from: context)
        case "clipboardClean":
            rawValue = primaryText(from: context).map(cleanText)
        case "clipboardUppercase":
            rawValue = primaryText(from: context).map { $0.uppercased() }
        case "clipboardLowercase":
            rawValue = primaryText(from: context).map { $0.lowercased() }
        case "clipboardTitleCase":
            rawValue = primaryText(from: context).map { $0.capitalized }
        case "clipboardSentenceCase":
            rawValue = primaryText(from: context).map(sentenceCase)
        case "clipboardHTML":
            rawValue = primaryHTML(from: context) ?? primaryText(from: context)
        case "clipboardURL":
            rawValue = context.snapshot.url?.absoluteString ?? primaryText(from: context)
        case "filePaths":
            let paths = context.snapshot.fileURLs?.map(\.path) ?? []
            rawValue = paths.isEmpty ? nil : paths.joined(separator: "\n")
        case "clipboardTrimmed":
            rawValue = primaryText(from: context)?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "charCount":
            if let text = primaryText(from: context) {
                rawValue = String(text.count)
            } else {
                rawValue = nil
            }
        case "lineCount":
            if let text = primaryText(from: context) {
                rawValue = String(text.components(separatedBy: .newlines).count)
            } else {
                rawValue = nil
            }
        default:
            throw ToolExecutionError.unsupportedParameterSource(name, property.source ?? "unknown")
        }

        guard let rawValue else { return nil }
        return (property.prefix ?? "") + rawValue + (property.suffix ?? "")
    }

    private func buildTemplateURL(from parameters: [String: String]) throws -> URL {
        guard let baseURL = parameters["baseURL"] else {
            throw ToolExecutionError.missingParameter("baseURL")
        }

        let path = parameters["path"]
        let fragment = parameters["fragment"]
        let queryItems = parameters
            .filter { !reservedURLKeys.contains($0.key) && !$0.key.hasPrefix(internalParameterPrefix) }
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        if let path, queryItems.isEmpty, fragment == nil, (baseURL.hasSuffix(":") || baseURL.hasSuffix("://")) {
            let encodedPath = percentEncodePath(path)
            return try ToolValidator.validateOpenableURL(baseURL + encodedPath)
        }

        guard var components = URLComponents(string: baseURL) else {
            throw ValidationError.invalidURL(baseURL)
        }

        if let path {
            components.percentEncodedPath = appendPath(path, to: components.percentEncodedPath)
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        if let fragment {
            components.fragment = fragment
        }

        guard let url = components.url else {
            throw ValidationError.invalidURL(baseURL)
        }

        return try ToolValidator.validateOpenableURL(url.absoluteString)
    }

    private func executeOpenApp(
        parameters: [String: String],
        completion: @escaping ActionCompletion
    ) throws {
        let appName = try requiredText(parameters["appName"])
        let bundleIdentifier = try ToolValidator.allowlistedBundleIdentifier(for: appName)
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw ToolExecutionError.applicationNotFound(appName)
        }

        let text = parameters["text"] ?? ""
        if !text.isEmpty {
            copyToClipboard(text)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    completion("Failed: \(error.localizedDescription)", false)
                } else if text.isEmpty {
                    completion("Opened \(appName)", false)
                } else {
                    completion("Opened \(appName) and copied prompt", true)
                }
            }
        }
    }

    private func executeOpenInTerminal(
        url: URL,
        completion: @escaping ActionCompletion
    ) throws {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw ToolExecutionError.applicationNotFound("Terminal")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: terminalURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    completion("Failed: \(error.localizedDescription)", false)
                } else {
                    completion("Opened in Terminal", false)
                }
            }
        }
    }

    private func executePing(host: String, completion: @escaping ActionCompletion) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "4", host]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                await MainActor.run {
                    if process.terminationStatus == 0 {
                        completion(output.isEmpty ? "Ping completed" : output, false)
                    } else {
                        completion(output.isEmpty ? "Ping failed" : output, false)
                    }
                }
            } catch {
                await MainActor.run {
                    completion("Failed: \(error.localizedDescription)", false)
                }
            }
        }
    }

    private func executeLLMPrompt(
        prompt: String,
        systemPrompt: String,
        promptSource: String?,
        context: ClipboardContext,
        completion: @escaping ActionCompletion,
        onToken: @escaping StreamCallback,
        onStatus: @escaping StatusCallback
    ) -> (() -> Void)? {
        let task = Task.detached { [weak self] in
            guard let self else { return }
            do {
                await self.ensureModelReady(onStatus: onStatus)
                let preparedPrompt = try await self.preparePromptForLLM(prompt, source: promptSource, context: context)
                let result = try await self.withLLMTimeout {
                    try await LocalLLMService.shared.generate(
                        prompt: self.truncate(preparedPrompt),
                        systemPrompt: systemPrompt,
                        temperature: 0.3,
                        maxTokens: 800,
                        onToken: { token in
                            Task { @MainActor in onToken(token) }
                        }
                    )
                }
                await MainActor.run {
                    self.copyToClipboard(result)
                    completion(result, true)
                }
            } catch is CancellationError {
                // Partial result already streamed via onToken
            } catch {
                await MainActor.run {
                    completion("Failed: \(error.localizedDescription)", false)
                }
            }
        }
        return { task.cancel() }
    }

    private func executeLLMAgent(
        prompt: String,
        systemPrompt: String,
        tools: [String],
        promptSource: String?,
        context: ClipboardContext,
        completion: @escaping ActionCompletion,
        onToken: @escaping StreamCallback,
        onStatus: @escaping StatusCallback
    ) -> (() -> Void)? {
        let task = Task.detached { [weak self] in
            guard let self else { return }
            do {
                await self.ensureModelReady(onStatus: onStatus)
                let preparedPrompt = try await self.preparePromptForLLM(prompt, source: promptSource, context: context)
                let combinedSystemPrompt = self.buildAgentSystemPrompt(systemPrompt, tools: tools)
                let result = try await self.withLLMTimeout {
                    try await LocalLLMService.shared.generate(
                        prompt: self.truncate(preparedPrompt),
                        systemPrompt: combinedSystemPrompt,
                        temperature: 0.3,
                        maxTokens: 800,
                        onToken: { token in
                            Task { @MainActor in onToken(token) }
                        }
                    )
                }

                // Try to parse as tool call
                if let toolCallResult = self.parseToolCallResponse(result) {
                    await MainActor.run {
                        self.executeToolCall(
                            toolCallResult,
                            context: context,
                            allowedTools: tools,
                            completion: completion
                        )
                    }
                } else {
                    await MainActor.run {
                        self.copyToClipboard(result)
                        completion(result, true)
                    }
                }
            } catch is CancellationError {
                // Partial result already streamed via onToken
            } catch {
                await MainActor.run {
                    completion("Failed: \(error.localizedDescription)", false)
                }
            }
        }
        return { task.cancel() }
    }

    nonisolated private func buildAgentSystemPrompt(_ userPrompt: String, tools: [String]) -> String {
        let toolDefs = tools.compactMap { name -> String? in
            guard let function = ExecuteFunction(rawValue: name) else { return nil }
            let paramName = agentToolParamName(function)
            return "- \(name)(\(paramName)): \(function.displayName)"
        }.joined(separator: "\n")

        return """
        \(userPrompt)

        Available tools:
        \(toolDefs)

        To use a tool, respond ONLY with JSON: {"tool": "name", "input": "the text"}
        Otherwise, respond with plain text.
        """
    }

    nonisolated private func agentToolParamName(_ function: ExecuteFunction) -> String {
        switch function {
        case .formatJSON: return "json"
        case .htmlToMarkdown: return "html"
        case .revealPath, .openInTerminal: return "path"
        case .ping: return "host"
        case .openURL, .openStaticURL, .openURLTemplate: return "url"
        case .openFile, .revealInFinder, .saveImage: return ""
        default: return "text"
        }
    }

    private struct ToolCallResponse {
        let tool: String
        let input: String
    }

    nonisolated private func parseToolCallResponse(_ response: String) -> ToolCallResponse? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code fences if present
        let cleaned: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let jsonLines = lines.dropFirst().prefix(while: { !$0.hasPrefix("```") })
            cleaned = jsonLines.joined(separator: "\n")
        } else {
            cleaned = trimmed
        }

        guard cleaned.hasPrefix("{"),
              let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String else {
            return nil
        }

        let input = json["input"] as? String ?? ""
        return ToolCallResponse(tool: tool, input: input)
    }

    private func executeToolCall(
        _ call: ToolCallResponse,
        context: ClipboardContext,
        allowedTools: [String],
        completion: @escaping ActionCompletion
    ) {
        guard allowedTools.contains(call.tool),
              let function = ExecuteFunction(rawValue: call.tool) else {
            completion("Failed: Tool '\(call.tool)' is not allowed", false)
            return
        }

        let paramName = agentToolParamName(function)
        let parameters = paramName.isEmpty ? [String: String]() : [paramName: call.input]
        execute(function: function, parameters: parameters, context: context, completion: completion)
    }

    private func executeSummarize(
        text: String,
        textSource: String?,
        context: ClipboardContext,
        completion: @escaping ActionCompletion,
        onToken: @escaping StreamCallback,
        onStatus: @escaping StatusCallback
    ) -> (() -> Void)? {
        let task = Task.detached { [weak self] in
            guard let self else { return }
            do {
                await self.ensureModelReady(onStatus: onStatus)
                let preparedText = try await self.preparePromptForLLM(text, source: textSource, context: context)
                let content = (textSource == "clipboardHTML")
                    ? HTMLMarkdownConverter.plainText(preparedText)
                    : preparedText
                let result = try await self.withLLMTimeout {
                    try await LLMService.shared.summarizeText(
                        self.truncate(content),
                        onToken: { token in
                            Task { @MainActor in onToken(token) }
                        }
                    )
                }
                await MainActor.run {
                    self.copyToClipboard(result)
                    completion(result, true)
                }
            } catch is CancellationError {
                // Partial result already streamed via onToken
            } catch {
                await MainActor.run {
                    completion("Failed: \(error.localizedDescription)", false)
                }
            }
        }
        return { task.cancel() }
    }

    private func ensureModelReady(onStatus: @escaping StatusCallback) async {
        let enabled = await MainActor.run { UserDefaults.standard.bool(forKey: "llmEnabled") }
        guard enabled else { return }
        let isReady = await LocalLLMService.shared.isReady
        if !isReady {
            await MainActor.run { onStatus("Loading model…") }
        }
    }

    private func executeHTMLToMarkdown(
        _ html: String,
        completion: @escaping ActionCompletion
    ) {
        Task.detached {
            do {
                let markdown = try await HTMLMarkdownConverter.convertAsync(html)
                await MainActor.run {
                    self.copyToClipboard(markdown)
                    completion(markdown, true)
                }
            } catch {
                Logger.error("HTML to Markdown conversion failed: \(error)", category: .actions)
                await MainActor.run {
                    completion("Failed: \(error.localizedDescription)", false)
                }
            }
        }
    }

    private func preparePromptForLLM(
        _ prompt: String,
        source: String?,
        context: ClipboardContext
    ) async throws -> String {
        guard source == "clipboardChatCleaned", context.sourceAppContext == .chat else {
            return prompt
        }

        let deterministic = ClipboardTextPreprocessor.sanitizeForLLM(prompt)

        do {
            let cleaned = try await LocalLLMService.shared.cleanChatTranscript(prompt)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleChatCleanup(trimmed, comparedTo: deterministic, raw: prompt) {
                return trimmed
            }
        } catch {
            Logger.warning("Chat cleanup fallback triggered: \(error)", category: .actions)
        }

        return deterministic.isEmpty ? prompt : deterministic
    }

    private func isPlausibleChatCleanup(
        _ cleaned: String,
        comparedTo fallback: String,
        raw: String
    ) -> Bool {
        guard !cleaned.isEmpty else { return false }

        let cleanedWords = wordCount(in: cleaned)
        let fallbackWords = wordCount(in: fallback)
        let rawWords = wordCount(in: raw)
        let cleanedTimestamps = matchCount(timestampRegex, in: cleaned)
        let rawTimestamps = matchCount(timestampRegex, in: raw)

        if cleanedWords < 6 {
            return false
        }

        if rawWords >= 40 && cleanedWords < max(10, rawWords / 8) {
            return false
        }

        if fallbackWords >= 20 && cleanedWords < max(8, fallbackWords / 3) {
            return false
        }

        if rawTimestamps >= 2 && cleanedTimestamps == 0 {
            return false
        }

        return true
    }

    nonisolated private func withLLMTimeout<T: Sendable>(
        seconds: TimeInterval = 25,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let operationTask = Task.detached(priority: .userInitiated) {
                try await operation()
            }

            Task.detached {
                do {
                    let result = try await operationTask.value
                    if resumed.withLock({ v -> Bool in guard !v else { return false }; v = true; return true }) {
                        continuation.resume(returning: result)
                    }
                } catch {
                    if resumed.withLock({ v -> Bool in guard !v else { return false }; v = true; return true }) {
                        continuation.resume(throwing: error)
                    }
                }
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if resumed.withLock({ v -> Bool in guard !v else { return false }; v = true; return true }) {
                    operationTask.cancel()
                    continuation.resume(throwing: ToolExecutionError.llmTimeout)
                }
            }
        }
    }

    private func executeSaveImage(completion: @escaping ActionCompletion) {
        guard let image = NSImage(pasteboard: .general) else {
            completion("Failed: No image found on the clipboard", false)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Clipboard.png"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                completion("Save cancelled", false)
                return
            }

            guard let tiff = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let data = representation.representation(using: .png, properties: [:]) else {
                completion("Failed: Could not process image", false)
                return
            }

            do {
                try data.write(to: url, options: .atomic)
                completion("Image saved", false)
            } catch {
                completion("Failed: \(error.localizedDescription)", false)
            }
        }
    }

    private func executeSaveTempFile(_ text: String, completion: @escaping ActionCompletion) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCopy", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("Clipboard-\(Int(Date().timeIntervalSince1970)).txt")
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
            completion("Saved temp file", false)
        } catch {
            completion("Failed: \(error.localizedDescription)", false)
        }
    }

    private func formatJSON(_ json: String) throws -> String {
        try ToolValidator.validateJSON(json)
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let formattedData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let formatted = String(data: formattedData, encoding: .utf8) else {
            throw ToolExecutionError.invalidStringOutput
        }
        return formatted
    }

    private func decodeBase64(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) else {
            throw ToolExecutionError.invalidBase64
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ToolExecutionError.nonUTF8Base64Payload
        }
        return decoded
    }

    private func stripANSI(_ text: String) -> String {
        let pattern = "\\x1B\\[[0-9;]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func primaryHTML(from context: ClipboardContext) -> String? {
        context.snapshot.htmlText
    }

    private func primaryText(from context: ClipboardContext) -> String? {
        context.snapshot.plainText ?? context.snapshot.url?.absoluteString
    }

    private func bestLLMText(from context: ClipboardContext) -> String? {
        ClipboardTextPreprocessor.bestLLMInput(from: context.snapshot)
            ?? primaryText(from: context)
    }

    private func sourceMetadataKey(for name: String) -> String {
        "\(internalParameterPrefix)source_\(name)"
    }

    private func sourceMetadata(named name: String, parameters: [String: String]) -> String? {
        parameters[sourceMetadataKey(for: name)]
    }

    private func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func matchCount(_ regex: NSRegularExpression, in text: String) -> Int {
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    private func cleanText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let unicodeReplacements: [(String, String)] = [
            ("\u{00A0}", " "),
            ("\u{1680}", " "),
            ("\u{2000}", " "),
            ("\u{2001}", " "),
            ("\u{2002}", " "),
            ("\u{2003}", " "),
            ("\u{2004}", " "),
            ("\u{2005}", " "),
            ("\u{2006}", " "),
            ("\u{2007}", " "),
            ("\u{2008}", " "),
            ("\u{2009}", " "),
            ("\u{200A}", " "),
            ("\u{202F}", " "),
            ("\u{205F}", " "),
            ("\u{3000}", " "),
            ("\u{200B}", ""),
            ("\u{200C}", ""),
            ("\u{200D}", ""),
            ("\u{2060}", ""),
            ("\u{FEFF}", ""),
            ("\u{00AD}", "")
        ]

        for (from, to) in unicodeReplacements {
            normalized = normalized.replacingOccurrences(of: from, with: to)
        }

        let lines = normalized.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var cleaned: [String] = []
        cleaned.reserveCapacity(lines.count)
        for line in lines {
            if line.isEmpty {
                if cleaned.last?.isEmpty == false {
                    cleaned.append("")
                }
            } else {
                cleaned.append(line)
            }
        }

        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sentenceCase(_ text: String) -> String {
        let cleaned = cleanText(text).lowercased()
        guard !cleaned.isEmpty else { return cleaned }

        var result = ""
        var capitalizeNext = true

        for character in cleaned {
            if capitalizeNext, String(character).rangeOfCharacter(from: .letters) != nil {
                result.append(String(character).uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
            }

            if ".!?".contains(character) {
                capitalizeNext = true
            }
        }

        return result
    }

    private func truncate(_ text: String, maxLength: Int = 3000) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "\n\n[Content truncated]"
    }

    private func requiredText(_ value: String?) throws -> String {
        guard let value, !value.isEmpty else {
            throw ToolExecutionError.missingClipboardText
        }
        return value
    }

    private func percentEncodePath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private func appendPath(_ path: String, to existingPath: String) -> String {
        let encodedSegments = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")

        if existingPath.isEmpty || existingPath == "/" {
            return "/" + encodedSegments.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let normalizedExisting = existingPath.hasSuffix("/") ? String(existingPath.dropLast()) : existingPath
        let normalizedNew = encodedSegments.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalizedExisting + "/" + normalizedNew
    }
}

enum ToolExecutionError: LocalizedError {
    case missingParameter(String)
    case missingClipboardText
    case missingFile
    case unsupportedParameterSource(String, String)
    case applicationNotFound(String)
    case invalidStringOutput
    case invalidBase64
    case nonUTF8Base64Payload
    case couldNotDecodeURL(String)
    case llmTimeout

    var errorDescription: String? {
        switch self {
        case let .missingParameter(name):
            return "Missing required parameter '\(name)'"
        case .missingClipboardText:
            return "No clipboard text was available for this tool"
        case .missingFile:
            return "No file was available on the clipboard"
        case let .unsupportedParameterSource(name, source):
            return "Unsupported source '\(source)' for parameter '\(name)'"
        case let .applicationNotFound(app):
            return "Could not locate the app '\(app)'"
        case .invalidStringOutput:
            return "The tool did not produce valid text output"
        case .invalidBase64:
            return "Clipboard text is not valid Base64"
        case .nonUTF8Base64Payload:
            return "Decoded Base64 data is not UTF-8 text"
        case let .couldNotDecodeURL(value):
            return "Could not decode URL-encoded text '\(value)'"
        case .llmTimeout:
            return "The AI action took too long to finish"
        }
    }
}
