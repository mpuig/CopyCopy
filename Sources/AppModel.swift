import Cocoa
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var statusText: String = "Double ⌘C to show actions."
    @Published var hasAccessibilityPermission: Bool = false
    @Published var lastClipboardContext: ClipboardContext?
    @Published var suggestedActions: [SuggestedAction] = []
    @Published var triggerPulseID: UUID = UUID()

    private let settings: AppSettings
    private let actionsStore: CustomActionsStore
    private let permissions = PermissionsManager()
    private let copyEventTap = CopyEventTap()
    private let pasteboardMonitor = PasteboardMonitor()
    private let classifier = ClipboardClassifier()

    private var lastCopyKeyEvent: CopyKeyEvent?
    private var lastTriggerTimestamp: TimeInterval?
    private var pendingShowRequestID: UUID?
    private var cancellables = Set<AnyCancellable>()

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
            let copyEvent = self.lastCopyKeyEvent.flatMap { (now - $0.timestamp) <= 1.0 ? $0 : nil }
            self.lastClipboardContext = ClipboardContext(copyEvent: copyEvent, snapshot: snapshot, capturedAt: now)
            self.statusText = snapshot.summary
            self.refreshSuggestions()
        }
        pasteboardMonitor.start()

        startEventTapIfPossible()
    }

    func refreshPermissions(promptIfNeeded: Bool) {
        hasAccessibilityPermission = permissions.hasAccessibilityPermission(promptIfNeeded: promptIfNeeded)
        print("[AppModel] Accessibility permission: \(hasAccessibilityPermission)")
        if hasAccessibilityPermission {
            let started = copyEventTap.start()
            print("[AppModel] Event tap start result: \(started)")
        } else {
            print("[AppModel] No permission, stopping event tap")
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
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard self.lastTriggerTimestamp == triggerTime else { return }
            self.captureClipboardForTrigger(copyEvent: copyEvent, capturedAt: CACurrentMediaTime())

            try? await Task.sleep(nanoseconds: 200_000_000)
            guard self.lastTriggerTimestamp == triggerTime else { return }
            self.captureClipboardForTrigger(copyEvent: copyEvent, capturedAt: CACurrentMediaTime())
        }
    }

    private func requestShowActions(copyEvent: CopyKeyEvent) {
        print("[AppModel] 🚀 requestShowActions called from \(copyEvent.appName)")
        let requestID = UUID()
        pendingShowRequestID = requestID
        beginTriggerFlow(copyEvent: copyEvent)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard self.pendingShowRequestID == requestID else {
                print("[AppModel] Request cancelled (new request came in)")
                return
            }
            print("[AppModel] 📢 Triggering pulse animation")
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

        suggestedActions = enabledActions.map { customAction in
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
