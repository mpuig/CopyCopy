import Cocoa
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var statusText: String = "Double ⌘C to show actions."
    @Published var hasAccessibilityPermission: Bool = false
    @Published var lastClipboardContext: ClipboardContext?
    @Published var suggestedActions: [SuggestedAction] = []
    @Published var triggerPulseID: UUID = UUID()
    @Published var isLLMLoading: Bool = false

    private let settings: AppSettings
    private let actionsStore: CustomActionsStore
    private let permissions = PermissionsManager()
    private let copyEventTap = CopyEventTap()
    private let pasteboardMonitor = PasteboardMonitor()
    private let classifier = ClipboardClassifier()
    private let llmSuggester = LLMActionSuggester()

    private var lastCopyKeyEvent: CopyKeyEvent?
    private var lastTriggerTimestamp: TimeInterval?
    private var pendingShowRequestID: UUID?
    private var cancellables = Set<AnyCancellable>()

    private enum Constants {
        /// First clipboard capture attempt delay (80ms) - Quick initial check to capture immediately available content
        static let clipboardCaptureDelay1: UInt64 = 80_000_000
        /// Second clipboard capture attempt delay (200ms) - Allows slower apps (browsers, IDEs) time to write large content to clipboard
        static let clipboardCaptureDelay2: UInt64 = 200_000_000
        /// Menu trigger delay (120ms) - Ensures clipboard capture completes before showing UI to prevent race conditions
        static let menuTriggerDelay: UInt64 = 120_000_000
        static let copyEventWindowSeconds: TimeInterval = 1.0
    }

    init(settings: AppSettings, actionsStore: CustomActionsStore) {
        self.settings = settings
        self.actionsStore = actionsStore
        self.copyEventTap.doublePressThreshold = settings.doubleCopyThresholdMs / 1000.0
        start()

        settings.$doubleCopyThresholdMs
            .sink { [weak self] newValue in
                self?.copyEventTap.doublePressThreshold = newValue / 1000.0
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
        if settings.llmEnabled && settings.useLocalLLM {
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
            Logger.info("Event tap start result: \(started)", category: .permissions)
        } else {
            Logger.info("No permission, stopping event tap", category: .permissions)
            copyEventTap.stop()
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
        if !copyEventTap.start() {
            statusText = "Could not start event tap. Check Accessibility / Input Monitoring."
        }
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
        Logger.info("requestShowActions called from \(copyEvent.appName)", category: .clipboard)
        let requestID = UUID()
        pendingShowRequestID = requestID
        beginTriggerFlow(copyEvent: copyEvent)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Constants.menuTriggerDelay)
            guard self.pendingShowRequestID == requestID else {
                Logger.info("Request cancelled (new request came in)", category: .clipboard)
                return
            }
            Logger.info("Triggering pulse animation", category: .clipboard)
            self.triggerPulseID = UUID()
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
        let entity = ctx.snapshot.detectedEntity
        let enabledActions = actionsStore.enabledActions(for: ctx.snapshot.kind, sourceContext: sourceContext, entity: entity)

        var actions: [SuggestedAction] = enabledActions.map { customAction in
            let actionCopy = customAction
            let contextCopy = ctx
            let storeCopy = actionsStore
            return SuggestedAction(
                title: actionCopy.name,
                subtitle: actionCopy.actionType.displayName,
                systemImage: actionCopy.systemImage
            ) {
                storeCopy.execute(actionCopy, with: contextCopy)
            }
        }

        // Add LLM-powered suggestions if enabled
        if settings.llmEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLLMLoading = true
                
                let llmSuggestions: [LLMSuggestedAction]
                if self.settings.useLocalLLM {
                    // Use local LLM
                    llmSuggestions = (try? await LocalLLMService.shared.suggestActions(clipboardContext: ctx)) ?? []
                } else {
                    // Use cloud LLM via HuggingFace
                    llmSuggestions = await self.llmSuggester.suggestActions(
                        for: ctx,
                        apiKey: self.settings.llmApiKey,
                        enabled: self.settings.llmEnabled
                    )
                }
                
                if !llmSuggestions.isEmpty {
                    let llmActions = self.llmSuggester.convertToSuggestedActions(
                        llmSuggestions: llmSuggestions,
                        context: ctx
                    )
                    actions.insert(contentsOf: llmActions, at: 0)
                    self.suggestedActions = actions
                }
                
                self.isLLMLoading = false
            }
        }

        suggestedActions = actions
    }

    func showAbout() {
        AboutPresenter.showAbout()
    }

    var menuBarSymbolName: String {
        guard hasAccessibilityPermission else { return "lock.slash" }
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
}
