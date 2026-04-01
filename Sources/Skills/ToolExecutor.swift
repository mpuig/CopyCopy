import Cocoa

@MainActor
final class ToolExecutor {
    typealias ActionCompletion = (_ text: String, _ isInClipboard: Bool) -> Void

    private let reservedURLKeys: Set<String> = ["baseURL", "path", "fragment"]

    func execute(
        tool: ToolDefinition,
        context: ClipboardContext,
        completion: @escaping ActionCompletion
    ) {
        do {
            let function = try ToolValidator.validateExecuteFunction(tool.execute)
            try ToolValidator.validateJSONObjectParameters(tool.parameters)
            let parameters = try resolveParameters(tool.parameters, context: context)
            execute(function: function, parameters: parameters, context: context, completion: completion)
        } catch {
            Logger.error("Tool execution failed for '\(tool.id)': \(error)", category: .actions)
            completion("Failed: \(error.localizedDescription)", false)
        }
    }

    private func execute(
        function: ExecuteFunction,
        parameters: [String: String],
        context: ClipboardContext,
        completion: @escaping ActionCompletion
    ) {
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
                completion("Copied to clipboard", true)

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
                let html = try requiredText(parameters["html"] ?? primaryText(from: context))
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
                executeLLMPrompt(prompt: prompt, systemPrompt: systemPrompt, completion: completion)

            case .summarize:
                let text = try requiredText(parameters["text"] ?? primaryText(from: context))
                executeSummarize(text: text, completion: completion)

            case .openStaticURL:
                guard let urlString = parameters["url"] else {
                    throw ToolExecutionError.missingParameter("url")
                }
                let url = try ToolValidator.validateOpenableURL(urlString)
                NSWorkspace.shared.open(url)
                completion("Opened URL", false)
            }
        } catch {
            Logger.error("Tool function \(function.rawValue) failed: \(error)", category: .actions)
            completion("Failed: \(error.localizedDescription)", false)
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
            .filter { !reservedURLKeys.contains($0.key) }
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
        completion: @escaping ActionCompletion
    ) {
        Task {
            do {
                let result = try await LocalLLMService.shared.generate(
                    prompt: truncate(prompt),
                    systemPrompt: systemPrompt,
                    temperature: 0.3,
                    maxTokens: 800
                )
                copyToClipboard(result)
                completion(result, true)
            } catch {
                completion("Failed: \(error.localizedDescription)", false)
            }
        }
    }

    private func executeSummarize(
        text: String,
        completion: @escaping ActionCompletion
    ) {
        let content = text.contains("<") && text.contains(">") ? SimpleHtmlConverter.toMarkdown(text) : text

        Task {
            do {
                let result = try await LLMService.shared.summarizeText(truncate(content))
                copyToClipboard(result)
                completion(result, true)
            } catch {
                completion("Failed: \(error.localizedDescription)", false)
            }
        }
    }

    private func executeHTMLToMarkdown(
        _ html: String,
        completion: @escaping ActionCompletion
    ) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["pandoc", "-f", "html", "-t", "markdown", "--wrap=none"]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                if let data = html.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
                inputPipe.fileHandleForWriting.closeFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let markdown = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !markdown.isEmpty {
                        await MainActor.run {
                            self.copyToClipboard(markdown)
                            completion(markdown, true)
                        }
                        return
                    }
                }
            } catch {
                Logger.debug("Pandoc unavailable for htmlToMarkdown: \(error)", category: .actions)
            }

            let markdown = SimpleHtmlConverter.toMarkdown(html)
            await MainActor.run {
                self.copyToClipboard(markdown)
                completion(markdown, true)
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

    private func primaryText(from context: ClipboardContext) -> String? {
        context.snapshot.plainText ?? context.snapshot.url?.absoluteString
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
        }
    }
}

enum SimpleHtmlConverter {
    static func toMarkdown(_ html: String) -> String {
        var markdown = html

        let removals: [(String, NSRegularExpression.Options)] = [
            ("<script[^>]*>[\\s\\S]*?</script>", .caseInsensitive),
            ("<style[^>]*>[\\s\\S]*?</style>", .caseInsensitive),
        ]

        for (pattern, options) in removals {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                markdown = regex.stringByReplacingMatches(
                    in: markdown,
                    range: NSRange(markdown.startIndex..., in: markdown),
                    withTemplate: ""
                )
            }
        }

        let replacements: [(String, String)] = [
            ("<strong[^>]*>([^<]*)</strong>", "**$1**"),
            ("<b[^>]*>([^<]*)</b>", "**$1**"),
            ("<em[^>]*>([^<]*)</em>", "*$1*"),
            ("<i[^>]*>([^<]*)</i>", "*$1*"),
            ("<a[^>]+href=\"([^\"]+)\"[^>]*>([^<]*)</a>", "[$2]($1)"),
            ("<li[^>]*>([^<]*)</li>", "- $1"),
            ("<p[^>]*>([^<]*)</p>", "\n\n$1\n\n"),
            ("<br\\s*/?>", "\n"),
        ]

        for (pattern, replacement) in replacements {
            markdown = markdown.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            markdown = tagRegex.stringByReplacingMatches(
                in: markdown,
                range: NSRange(markdown.startIndex..., in: markdown),
                withTemplate: ""
            )
        }

        markdown = markdown.replacingOccurrences(of: "\n\\s*\n\\s*\n", with: "\n\n", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&nbsp;", " "),
        ]

        for (entity, character) in entities {
            markdown = markdown.replacingOccurrences(of: entity, with: character)
        }

        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
