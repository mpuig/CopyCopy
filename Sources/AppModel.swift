import Cocoa
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var statusText: String = "Double ⌘C to show actions."
    @Published var hasAccessibilityPermission: Bool = false
    @Published var isEventTapRunning: Bool = false
    @Published var lastClipboardContext: ClipboardContext?
    @Published var suggestedActions: [SuggestedAction] = []
    @Published var triggerPulseID: UUID = UUID()

    private let settings: AppSettings
    private let skillLoader = SkillLoader()
    private let actionExecutor = ToolExecutor()
    private let permissions = PermissionsManager()
    private let copyEventTap = CopyEventTap()
    private let pasteboardMonitor = PasteboardMonitor()
    private let classifier = ClipboardClassifier()

    private var lastCopyKeyEvent: CopyKeyEvent?
    private var lastTriggerTimestamp: TimeInterval?
    private var pendingShowRequestID: UUID?
    private var semanticClassificationTask: Task<Void, Never>?
    private var semanticClassificationCache: [String: [DetectedEntityType]] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var floatingPanel: FloatingActionPanel?

    private enum Constants {
        /// First clipboard capture attempt delay (80ms) - Quick initial check to capture immediately available content
        static let clipboardCaptureDelay1: UInt64 = 80_000_000
        /// Second clipboard capture attempt delay (200ms) - Allows slower apps (browsers, IDEs) time to write large content to clipboard
        static let clipboardCaptureDelay2: UInt64 = 200_000_000
        /// Menu trigger delay (120ms) - Ensures clipboard capture completes before showing UI to prevent race conditions
        static let menuTriggerDelay: UInt64 = 120_000_000
        static let copyEventWindowSeconds: TimeInterval = 1.0
        static let permissionRefreshInterval: TimeInterval = 1.5
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.copyEventTap.doublePressThreshold = settings.doubleCopyThresholdMs / 1000.0
        start()

        settings.$doubleCopyThresholdMs
            .sink { [weak self] newValue in
                self?.copyEventTap.doublePressThreshold = newValue / 1000.0
            }
            .store(in: &cancellables)

        Timer.publish(every: Constants.permissionRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.hasAccessibilityPermission || !self.isEventTapRunning else { return }
                self.refreshPermissions(promptIfNeeded: false)
            }
            .store(in: &cancellables)
    }

    private func start() {
        refreshPermissions(promptIfNeeded: true)

        copyEventTap.onCopyKeyDown = { [weak self] copyEvent in
            guard let self else { return }
            self.lastCopyKeyEvent = copyEvent
            self.statusText = "Copied in \(copyEvent.appName) (\(copyEvent.bundleID ?? "unknown"))."
        }

        copyEventTap.onDoubleCopy = { [weak self] copyEvent in
            guard let self else { return }
            self.lastCopyKeyEvent = copyEvent
            self.statusText = "Triggered from \(copyEvent.appName)."
            self.requestShowActions(copyEvent: copyEvent)
        }

        pasteboardMonitor.onChange = { [weak self] changeCount in
            guard let self else { return }
            let snapshot = self.classifier.snapshot(from: .general, changeCount: changeCount)

            let now = CACurrentMediaTime()
            let copyEvent = self.lastCopyKeyEvent.flatMap { (now - $0.timestamp) <= Constants.copyEventWindowSeconds ? $0 : nil }
            self.lastClipboardContext = ClipboardContext(copyEvent: copyEvent, snapshot: snapshot, capturedAt: now)
            self.statusText = snapshot.summary
            self.refreshSuggestions()
        }
        pasteboardMonitor.start()

        startEventTapIfPossible()
        
        // Preload local LLM model if enabled
        if settings.llmEnabled {
            Task {
                await LocalLLMService.shared.loadModel()
            }
        }
    }

    func refreshPermissions(promptIfNeeded: Bool) {
        hasAccessibilityPermission = permissions.hasAccessibilityPermission(promptIfNeeded: promptIfNeeded)
        Logger.info("Accessibility permission: \(hasAccessibilityPermission)", category: .permissions)
        if hasAccessibilityPermission {
            let started = copyEventTap.start()
            isEventTapRunning = started && copyEventTap.isRunning
            Logger.info("Event tap start result: \(started)", category: .permissions)
        } else {
            Logger.info("No permission, stopping event tap", category: .permissions)
            copyEventTap.stop()
            isEventTapRunning = false
        }
    }

    func openAccessibilitySettings() {
        permissions.openAccessibilitySettings()
    }

    func openInputMonitoringSettings() {
        permissions.openInputMonitoringSettings()
    }

    private func startEventTapIfPossible() {
        guard hasAccessibilityPermission else { return }
        let started = copyEventTap.start()
        isEventTapRunning = started && copyEventTap.isRunning
        if !started {
            statusText = "Could not start event tap. Check Accessibility / Input Monitoring."
        }
    }

    func refreshRuntimeAccessStatus() {
        refreshPermissions(promptIfNeeded: false)
    }

    private func beginTriggerFlow(copyEvent: CopyKeyEvent) {
        suggestedActions = []
        let triggerTime = CACurrentMediaTime()
        lastTriggerTimestamp = triggerTime

        captureClipboardForTrigger(copyEvent: copyEvent, capturedAt: triggerTime)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Constants.clipboardCaptureDelay1)
            guard self.lastTriggerTimestamp == triggerTime else { return }
            self.captureClipboardForTrigger(copyEvent: copyEvent, capturedAt: CACurrentMediaTime())

            try? await Task.sleep(nanoseconds: Constants.clipboardCaptureDelay2)
            guard self.lastTriggerTimestamp == triggerTime else { return }
            self.captureClipboardForTrigger(copyEvent: copyEvent, capturedAt: CACurrentMediaTime())
        }
    }

    private func requestShowActions(copyEvent: CopyKeyEvent) {
        Logger.info("[AppModel] requestShowActions called from \(copyEvent.appName)", category: .clipboard)
        let requestID = UUID()
        pendingShowRequestID = requestID
        beginTriggerFlow(copyEvent: copyEvent)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Constants.menuTriggerDelay)
            guard self.pendingShowRequestID == requestID else {
                Logger.info("[AppModel] Request cancelled (new request came in)", category: .clipboard)
                return
            }
            Logger.info("[AppModel] Showing floating panel", category: .clipboard)

            // If a panel is already showing an executed action, just dismiss it
            if let existing = self.floatingPanel, existing.isVisible {
                existing.close()
                self.floatingPanel = nil
                return
            }

            self.floatingPanel?.close()

            if let context = self.lastClipboardContext {
                let panel = FloatingActionPanel(
                    context: context,
                    actions: self.suggestedActions,
                    onActionStarted: { [weak self] in
                        self?.semanticClassificationTask?.cancel()
                        self?.semanticClassificationTask = nil
                    }
                )
                self.floatingPanel = panel
                panel.show()
            }
        }
    }

    private func captureClipboardForTrigger(copyEvent: CopyKeyEvent, capturedAt: TimeInterval) {
        let changeCount = NSPasteboard.general.changeCount

        if let existing = lastClipboardContext,
           let triggerAt = lastTriggerTimestamp,
           existing.capturedAt >= triggerAt,
           existing.snapshot.changeCount == changeCount
        {
            refreshSuggestions()
            return
        }

        let snapshot = classifier.snapshot(from: .general, changeCount: changeCount)
        lastClipboardContext = ClipboardContext(copyEvent: copyEvent, snapshot: snapshot, capturedAt: capturedAt)
        statusText = snapshot.summary
        refreshSuggestions()
    }

    func refreshSuggestions() {
        guard let ctx = lastClipboardContext else {
            suggestedActions = []
            return
        }

        let sourceContext = ctx.sourceAppContext

        let actions = skillLoader.matchingActions(
            for: ctx.snapshot.kind,
            sourceContext: sourceContext,
            entities: ctx.snapshot.detectedEntities,
            context: ctx,
            executor: actionExecutor
        )

        suggestedActions = actions
        scheduleSemanticClassificationIfNeeded(for: ctx)
    }

    private func scheduleSemanticClassificationIfNeeded(for context: ClipboardContext) {
        guard settings.llmEnabled, LocalLLMService.shared.isReady else { return }
        guard context.snapshot.kind == .plainText, let text = context.snapshot.plainText else { return }
        guard shouldRunSemanticClassification(for: text, entities: context.snapshot.detectedEntities) else { return }

        let cacheKey = semanticClassificationCacheKey(for: text)
        if let cached = semanticClassificationCache[cacheKey] {
            applySemanticClassification(cached, to: context)
            return
        }

        semanticClassificationTask?.cancel()
        let changeCount = context.snapshot.changeCount
        let capturedAt = context.capturedAt

        semanticClassificationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let tags = try await LocalLLMService.shared.classifyTextEntities(text)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.semanticClassificationCache[cacheKey] = tags
                    guard let current = self.lastClipboardContext,
                          current.snapshot.changeCount == changeCount,
                          current.capturedAt == capturedAt else {
                        return
                    }
                    self.applySemanticClassification(tags, to: current)
                }
            } catch {
                Logger.warning("Semantic text classification failed: \(error)", category: .general)
            }
        }
    }

    private func applySemanticClassification(_ tags: [DetectedEntityType], to context: ClipboardContext) {
        guard !tags.isEmpty else { return }

        let mergedSnapshot = context.snapshot.merged(with: tags, summary: semanticSummary(for: context.snapshot, additionalTags: tags))
        guard mergedSnapshot.detectedEntities != context.snapshot.detectedEntities else { return }

        lastClipboardContext = ClipboardContext(
            copyEvent: context.copyEvent,
            snapshot: mergedSnapshot,
            capturedAt: context.capturedAt
        )
        refreshSuggestions()
    }

    private func shouldRunSemanticClassification(for text: String, entities: [DetectedEntityType]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24, trimmed.count <= 4000 else { return false }

        let existingTags = Set(entities)
        let semanticTags: Set<DetectedEntityType> = [.emailDraft, .slackDraft, .shellCommand, .logOutput, .sql]
        guard semanticTags.isDisjoint(with: existingTags) else { return false }

        let strongDetections: Set<DetectedEntityType> = [
            .json, .base64, .urlEncoded, .html, .markdown, .codeSnippet, .email, .phoneNumber, .address, .coordinates,
            .filePath, .ipAddress, .uuid, .currency, .date, .transitInfo, .trackingNumber
        ]
        if !strongDetections.isDisjoint(with: existingTags) {
            return false
        }

        return true
    }

    private func semanticClassificationCacheKey(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed.count):\(trimmed)"
    }

    private func semanticSummary(for snapshot: ClipboardSnapshot, additionalTags: [DetectedEntityType]) -> String {
        guard let firstTag = additionalTags.first else { return snapshot.summary }
        guard !snapshot.summary.contains(firstTag.displayName) else { return snapshot.summary }
        return snapshot.summary + " • " + firstTag.displayName
    }

    func showAbout() {
        AboutPresenter.showAbout()
    }

    var menuBarSymbolName: String {
        guard hasAccessibilityPermission else { return "lock.slash" }
        guard isEventTapRunning else { return "exclamationmark.triangle" }
        guard let kind = lastClipboardContext?.snapshot.kind else { return "doc.on.doc" }

        switch kind {
        case .url: return "link"
        case .fileURLs: return "folder"
        case .image: return "photo"
        case .plainText: return "text.quote"
        case .richText: return "doc.richtext"
        case .unknown: return "questionmark.folder"
        }
    }

    var permissionPromptTitle: String? {
        if !hasAccessibilityPermission {
            return "Grant Accessibility Permission…"
        }
        if !isEventTapRunning {
            return "Grant Input Monitoring Permission…"
        }
        return nil
    }

    func resolvePermissionPromptAction() {
        if !hasAccessibilityPermission {
            openAccessibilitySettings()
        } else if !isEventTapRunning {
            openInputMonitoringSettings()
        }
    }
}
