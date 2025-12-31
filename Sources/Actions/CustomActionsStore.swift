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
            print("[CustomActionsStore] Failed to decode actions: \(error)")
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
            print("[CustomActionsStore] Failed to encode actions: \(error)")
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

    func execute(_ action: CustomAction, with context: ClipboardContext) {
        let text = context.snapshot.plainText ?? context.snapshot.url?.absoluteString ?? ""
        var processedTemplate = action.processTemplate(with: text)

        if let fileURL = context.snapshot.fileURLs?.first {
            processedTemplate = processedTemplate.replacingOccurrences(of: "{path}", with: fileURL.path)
        }

        switch action.actionType {
        case .openURL:
            executeOpenURL(processedTemplate)
        case .shellCommand:
            executeShellCommand(processedTemplate)
        case .openApp:
            executeOpenApp(action, processedText: processedTemplate)
        case .revealInFinder:
            executeRevealInFinder(context)
        case .openFile:
            executeOpenFile(context)
        case .copyToClipboard:
            executeCopyToClipboard(processedTemplate)
        case .saveImage:
            executeSaveImage()
        case .saveTempFile:
            executeSaveTempFile(text)
        case .stripANSI:
            executeStripANSI(text)
        }
    }

    private func executeOpenURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            print("[CustomActionsStore] Invalid URL: \(urlString)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func executeShellCommand(_ command: String) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            do {
                try process.run()
            } catch {
                print("[CustomActionsStore] Failed to run command: \(error)")
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
                print("[CustomActionsStore] AppleScript error: \(error)")
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
        guard let image = NSImage(pasteboard: .general) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Clipboard.png"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func executeSaveTempFile(_ text: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCopy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("Clipboard-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            print("[CustomActionsStore] Failed to save temp file: \(error)")
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

    private func extractAppName(from template: String) -> String? {
        if template.lowercased().contains("chatgpt") {
            return "ChatGPT"
        }
        if template.lowercased().contains("claude") {
            return "Claude"
        }
        return nil
    }
}
