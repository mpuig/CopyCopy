import Cocoa
import Foundation

@MainActor
final class CustomActionsStore: ObservableObject {
    @Published var actions: [CustomAction] = []

    private let storageKey = "customActions"
    private let hasInitializedKey = "customActionsInitialized"

    init() {
        loadActions()
    }

    func loadActions() {
        let hasInitialized = UserDefaults.standard.bool(forKey: hasInitializedKey)

        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            if !hasInitialized {
                actions = CustomAction.defaultActions
                saveActions()
                UserDefaults.standard.set(true, forKey: hasInitializedKey)
            } else {
                actions = []
            }
            return
        }

        do {
            actions = try JSONDecoder().decode([CustomAction].self, from: data)
            if !hasInitialized {
                mergeDefaultActions()
                UserDefaults.standard.set(true, forKey: hasInitializedKey)
            }
        } catch {
            Logger.error("Failed to decode actions: \(error)", category: .actions)
            actions = CustomAction.defaultActions
            saveActions()
            UserDefaults.standard.set(true, forKey: hasInitializedKey)
        }
    }

    private func mergeDefaultActions() {
        let existingIDs = Set(actions.map { $0.id })
        for defaultAction in CustomAction.defaultActions where !existingIDs.contains(defaultAction.id) {
            actions.insert(defaultAction, at: 0)
        }
        saveActions()
    }

    func resetToDefaults() {
        actions = CustomAction.defaultActions
        saveActions()
    }

    func saveActions() {
        do {
            let data = try JSONEncoder().encode(actions)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Logger.error("Failed to encode actions: \(error)", category: .actions)
        }
    }

    func addAction(_ action: CustomAction) {
        actions.append(action)
        saveActions()
    }

    func updateAction(_ action: CustomAction) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
            saveActions()
        }
    }

    func removeAction(_ action: CustomAction) {
        actions.removeAll { $0.id == action.id }
        saveActions()
    }

    func removeActions(at offsets: IndexSet) {
        actions.remove(atOffsets: offsets)
        saveActions()
    }

    func moveActions(from source: IndexSet, to destination: Int) {
        actions.move(fromOffsets: source, toOffset: destination)
        saveActions()
    }

    func enabledActions(for contentKind: ClipboardContentKind, sourceContext: SourceAppContext, entity: DetectedEntityType) -> [CustomAction] {
        actions.filter {
            $0.isEnabled &&
            $0.contentFilter.matches(contentKind) &&
            $0.sourceFilter.matches(sourceContext) &&
            $0.entityFilter.matches(entity)
        }
    }

    /// Completion passed back after an action finishes.
    /// - `text`: human-readable result description
    /// - `isInClipboard`: whether the result was placed on the pasteboard
    typealias ActionCompletion = (_ text: String, _ isInClipboard: Bool) -> Void

    func execute(_ action: CustomAction, with context: ClipboardContext, completion: ActionCompletion? = nil) {
        let text = context.snapshot.plainText ?? context.snapshot.url?.absoluteString ?? ""
        let shouldEscape = action.actionType == .shellCommand
        var processedTemplate = action.processTemplate(with: text, shouldEscapeForShell: shouldEscape)

        if let fileURLs = context.snapshot.fileURLs {
            if fileURLs.count == 1 {
                processedTemplate = processedTemplate.replacingOccurrences(of: "{path}", with: fileURLs[0].path)
            } else if fileURLs.count > 1 {
                let paths = fileURLs.map { $0.path }.joined(separator: " ")
                processedTemplate = processedTemplate.replacingOccurrences(of: "{path}", with: paths)
            }
        }

        switch action.actionType {
        case .openURL:
            executeOpenURL(processedTemplate)
            completion?("Opened URL", false)
        case .shellCommand:
            executeShellCommand(processedTemplate, completion: completion)
        case .openApp:
            executeOpenApp(action, processedText: processedTemplate)
            completion?("Opened \(extractAppName(from: action.template) ?? "app")", false)
        case .revealInFinder:
            executeRevealInFinder(context)
            completion?("Revealed in Finder", false)
        case .openFile:
            executeOpenFile(context)
            completion?("Opened file", false)
        case .copyToClipboard:
            executeCopyToClipboard(processedTemplate)
            completion?("Copied to clipboard", true)
        case .saveImage:
            executeSaveImage()
            completion?("Image saved", false)
        case .saveTempFile:
            executeSaveTempFile(text)
            completion?("Saved temp file", false)
        case .stripANSI:
            executeStripANSI(text)
            completion?("ANSI codes stripped", true)
        case .htmlToMarkdown:
            executeHtmlToMarkdown(text, completion: completion)
        case .summarize:
            executeSummarize(text, completion: completion)
        }
    }

    private func executeOpenURL(_ urlString: String) {
        guard let url = URL(string: urlString), url.scheme != nil else {
            Logger.warning("Invalid URL: \(urlString)", category: .actions)
            showErrorAlert(title: "Invalid URL", message: "The URL could not be opened.")
            return
        }
        
        let validSchemes = ["http", "https", "mailto", "tel", "facetime", "maps", "dict", "calshow", "addressbook"]
        guard let scheme = url.scheme?.lowercased(), validSchemes.contains(scheme) else {
            Logger.warning("Potentially unsafe URL scheme: \(url.scheme ?? "unknown")", category: .actions)
            showErrorAlert(title: "Unsafe URL", message: "This URL scheme is not allowed.")
            return
        }
        
        NSWorkspace.shared.open(url)
    }

    private func executeShellCommand(_ command: String, completion: ActionCompletion? = nil) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    Logger.error("Command failed with exit code \(process.terminationStatus): \(output)", category: .actions)
                    await MainActor.run { completion?("Command failed: \(output)", false) }
                } else {
                    await MainActor.run { completion?(output.isEmpty ? "Command completed" : output, false) }
                }
            } catch {
                Logger.error("Failed to run command: \(error)", category: .actions)
                await MainActor.run { completion?("Failed: \(error.localizedDescription)", false) }
            }
        }
    }

    private func executeOpenApp(_ action: CustomAction, processedText: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(processedText, forType: .string)

        let appName = extractAppName(from: action.template) ?? "ChatGPT"

        let script = """
        tell application "\(appName)"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                Logger.error("AppleScript error: \(error)", category: .actions)
                Task { @MainActor in
                    self.showErrorAlert(title: "Failed to Open App", message: "Could not open \(appName).")
                }
            }
        }
    }

    private func executeRevealInFinder(_ context: ClipboardContext) {
        guard let urls = context.snapshot.fileURLs, !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func executeOpenFile(_ context: ClipboardContext) {
        guard let url = context.snapshot.fileURLs?.first else { return }
        NSWorkspace.shared.open(url)
    }

    private func executeCopyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func executeSaveImage() {
        guard let image = NSImage(pasteboard: .general) else {
            showErrorAlert(title: "No Image", message: "No image found on the clipboard.")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Clipboard.png"

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
                self?.showErrorAlert(title: "Image Error", message: "Could not process the image.")
                return
            }
            
            guard let data = rep.representation(using: .png, properties: [:]) else {
                self?.showErrorAlert(title: "Image Error", message: "Could not convert image to PNG.")
                return
            }
            
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self?.showErrorAlert(title: "Save Failed", message: "Could not save image: \(error.localizedDescription)")
            }
        }
    }

    private func executeSaveTempFile(_ text: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCopy", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Logger.error("Failed to create temp directory: \(error)", category: .actions)
            showErrorAlert(title: "Save Failed", message: "Could not create temporary directory.")
            return
        }

        let fileURL = dir.appendingPathComponent("Clipboard-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            Logger.error("Failed to save temp file: \(error)", category: .actions)
            showErrorAlert(title: "Save Failed", message: "Could not save file: \(error.localizedDescription)")
        }
    }

    private func executeStripANSI(_ text: String) {
        let pattern = "\\x1B\\[[0-9;]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(stripped, forType: .string)
    }

    private func executeHtmlToMarkdown(_ html: String, completion: ActionCompletion? = nil) {
        _ = Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["pandoc", "-f", "html", "-t", "markdown", "--wrap=none"]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe

            do {
                try process.run()

                if let data = html.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                    inputPipe.fileHandleForWriting.closeFile()
                }

                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let markdown = String(data: data, encoding: .utf8) {
                        await MainActor.run {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(markdown, forType: .string)
                            completion?("Converted to Markdown", true)
                        }
                        return
                    }
                }
            } catch {
                Logger.debug("Pandoc not available, using fallback: \(error)", category: .actions)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                let markdown = self.simpleHtmlToMarkdown(html)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
                completion?("Converted to Markdown", true)
            }
        }
    }
    
    private func simpleHtmlToMarkdown(_ html: String) -> String {
        // Simple HTML to Markdown conversion
        var markdown = html
        
        // Remove script and style tags with their content
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        if let regex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) {
            markdown = regex.stringByReplacingMatches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown), withTemplate: "")
        }
        
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"
        if let regex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            markdown = regex.stringByReplacingMatches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown), withTemplate: "")
        }
        
        // Convert headers
        for i in (1...6).reversed() {
            let pattern = "<h\\(i)[^>]*>([^<]*)</h\\(i)>"
            let replacement = String(repeating: "#", count: i) + " $2"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                markdown = regex.stringByReplacingMatches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown), withTemplate: replacement)
            }
        }
        
        // Convert bold and italic
        markdown = markdown.replacingOccurrences(of: "<strong[^>]*>([^<]*)</strong>", with: "**$1**", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<b[^>]*>([^<]*)</b>", with: "**$1**", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<em[^>]*>([^<]*)</em>", with: "*$1*", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<i[^>]*>([^<]*)</i>", with: "*$1*", options: .regularExpression)
        
        // Convert links
        markdown = markdown.replacingOccurrences(of: "<a[^>]+href=\"([^\"]+)\"[^>]*>([^<]*)</a>", with: "[$2]($1)", options: .regularExpression)
        
        // Convert images
        markdown = markdown.replacingOccurrences(of: "<img[^>]+src=\"([^\"]+)\"[^>]*alt=\"([^\"]*)\"[^>]*>", with: "![$2]($1)", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<img[^>]+alt=\"([^\"]*)\"[^>]+src=\"([^\"]+)\"[^>]*>", with: "![$1]($2)", options: .regularExpression)
        markdown = markdown.replacingOccurrences(of: "<img[^>]+src=\"([^\"]+)\"[^>]*>", with: "![]($1)", options: .regularExpression)
        
        // Convert lists
        markdown = markdown.replacingOccurrences(of: "<li[^>]*>([^<]*)</li>", with: "- $1", options: .regularExpression)
        
        // Convert paragraphs
        markdown = markdown.replacingOccurrences(of: "<p[^>]*>([^<]*)</p>", with: "\n\n$1\n\n", options: .regularExpression)
        
        // Convert line breaks
        markdown = markdown.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        
        // Remove remaining HTML tags
        let tagPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            markdown = regex.stringByReplacingMatches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown), withTemplate: "")
        }
        
        // Clean up multiple newlines
        markdown = markdown.replacingOccurrences(of: "\n\\s*\n\\s*\n", with: "\n\n", options: .regularExpression)
        
        // Decode HTML entities
        markdown = markdown.replacingOccurrences(of: "&lt;", with: "<")
        markdown = markdown.replacingOccurrences(of: "&gt;", with: ">")
        markdown = markdown.replacingOccurrences(of: "&amp;", with: "&")
        markdown = markdown.replacingOccurrences(of: "&quot;", with: "\"")
        markdown = markdown.replacingOccurrences(of: "&#39;", with: "'")
        markdown = markdown.replacingOccurrences(of: "&nbsp;", with: " ")
        
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func executeSummarize(_ text: String, completion: ActionCompletion? = nil) {
        let contentToSummarize: String
        if text.contains("<") && text.contains(">") {
            contentToSummarize = simpleHtmlToMarkdown(text)
        } else {
            contentToSummarize = text
        }

        let maxLength = 3000
        let truncatedContent = contentToSummarize.count > maxLength
            ? String(contentToSummarize.prefix(maxLength)) + "\n\n[Content truncated for summarization]"
            : contentToSummarize

        Task {
            do {
                let summary = try await LLMService.shared.summarizeText(truncatedContent)
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                    completion?(summary, true)
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to summarize: \(error)", category: .actions)
                    completion?("Summarization failed: \(error.localizedDescription)", false)
                }
            }
        }
    }
    
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func extractAppName(from template: String) -> String? {
        let appMappings: [String: String] = [
            "chatgpt": "ChatGPT",
            "openai": "ChatGPT",
            "claude": "Claude",
            "anthropic": "Claude",
            "cursor": "Cursor",
            "copilot": "Copilot"
        ]

        let lowercaseTemplate = template.lowercased()

        for (keyword, appName) in appMappings {
            if lowercaseTemplate.contains(keyword) {
                return appName
            }
        }

        return nil
    }
    
    private func showErrorAlert(title: String, message: String) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
