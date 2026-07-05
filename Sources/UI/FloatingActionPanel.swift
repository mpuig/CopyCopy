import Cocoa
import SwiftUI
import Combine

@MainActor
class FloatingActionPanel: NSPanel {
    private let contentViewModel: FloatingPanelViewModel
    private var cancellables = Set<AnyCancellable>()
    private var keyEventMonitor: Any?

    init(context: ClipboardContext, actions: [SuggestedAction], skillLoader: SkillLoader, executor: ToolExecutor, onActionStarted: (() -> Void)? = nil) {
        self.contentViewModel = FloatingPanelViewModel(context: context, actions: actions, skillLoader: skillLoader, executor: executor)
        contentViewModel.onActionStarted = onActionStarted

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupContent()
        setupBindings()
        setupEventMonitor()
        positionWindowNearCursor()

        contentViewModel.requestClose = { [weak self] in
            self?.close()
        }
    }

    private func setupWindow() {
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
    }

    private func setupContent() {
        let hostingView = NSHostingView(rootView: FloatingPanelView(viewModel: contentViewModel))
        contentView = hostingView
    }

    private func setupBindings() {
        contentViewModel.$processingState
            .combineLatest(contentViewModel.$resultText, contentViewModel.$executedAction, contentViewModel.$followUpActions)
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _, _, _, _ in
                self?.resizeForCurrentContent(animated: true)
            }
            .store(in: &cancellables)
    }

    private func setupEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.window === self else { return event }

            // The ask TextField is always focused, so ↑/↓/Return/Esc are
            // intercepted here (before the field's editor sees them) to drive
            // the shortcut list and freeform routing. Other keys (typing,
            // ←/→ cursor motion) fall through to the field.
            let vm = self.contentViewModel
            switch event.keyCode {
            case 126: // up
                vm.selectPrevious()
                return nil
            case 125: // down
                vm.selectNext()
                return nil
            case 36: // return
                if vm.executedAction == nil {
                    vm.handleTriggerReturn()
                } else {
                    vm.executeSelected()
                }
                return nil
            case 53: // esc
                if vm.executedAction == nil, !vm.askText.isEmpty {
                    vm.askText = ""
                } else if vm.isGenerating {
                    vm.stopGeneration()
                } else if vm.executedAction != nil {
                    vm.resetToActions()
                } else {
                    self.close()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func positionWindowNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        guard let screen = screen else { return }

        let panelSize = CGSize(width: 392, height: desiredPanelHeight())
        var origin = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height - 20
        )

        if origin.x < screen.frame.minX {
            origin.x = screen.frame.minX + 10
        }
        if origin.x + panelSize.width > screen.frame.maxX {
            origin.x = screen.frame.maxX - panelSize.width - 10
        }
        if origin.y < screen.frame.minY {
            origin.y = mouseLocation.y + 20
        }

        setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func resizeForCurrentContent(animated: Bool) {
        let newHeight = desiredPanelHeight()
        let currentFrame = frame
        guard abs(currentFrame.height - newHeight) > 1 else { return }

        var newFrame = currentFrame
        newFrame.origin.y -= (newHeight - currentFrame.height)
        newFrame.size.height = newHeight

        if let screen = screen ?? NSScreen.screens.first(where: { $0.frame.intersects(currentFrame) }) {
            if newFrame.origin.y < screen.frame.minY + 10 {
                newFrame.origin.y = screen.frame.minY + 10
            }
            if newFrame.maxY > screen.frame.maxY - 10 {
                newFrame.origin.y = screen.frame.maxY - newFrame.height - 10
            }
        }

        setFrame(newFrame, display: true, animate: animated)
    }

    private func desiredPanelHeight() -> CGFloat {
        // Trigger state adds the always-focused ask field above the shortcuts.
        if contentViewModel.executedAction == nil {
            return min(320, 150 + CGFloat(contentViewModel.actions.count) * 50)
        }

        switch contentViewModel.processingState {
        case .idle:
            return min(320, 150 + CGFloat(contentViewModel.actions.count) * 50)
        case .processing:
            return 150
        case .completed:
            let followUpHeight = CGFloat(contentViewModel.followUpActions.count) * 40
            let backButtonHeight: CGFloat = 40
            if let resultText = contentViewModel.resultText, !resultText.isEmpty {
                let lineCount = max(1, resultText.components(separatedBy: .newlines).count)
                let previewHeight = min(300, max(100, CGFloat(lineCount) * 18))
                return min(700, 120 + previewHeight + (contentViewModel.isResultInClipboard ? 28 : 0) + followUpHeight + backButtonHeight)
            }
            return contentViewModel.isResultInClipboard ? 170 : 150
        }
    }

    func show() {
        makeKeyAndOrderFront(nil)
        becomeFirstResponder()

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.contentViewModel.processingState == .idle {
                self?.close()
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        contentViewModel.stopGeneration()
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        super.close()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: contentViewModel.selectPrevious()
        case 125: contentViewModel.selectNext()
        case 36:
            if contentViewModel.executedAction == nil {
                contentViewModel.handleTriggerReturn()
            } else {
                contentViewModel.executeSelected()
            }
        case 53:
            if contentViewModel.executedAction == nil, !contentViewModel.askText.isEmpty {
                contentViewModel.askText = ""
            } else if contentViewModel.isGenerating {
                contentViewModel.stopGeneration()
            } else if contentViewModel.executedAction != nil {
                contentViewModel.resetToActions()
            } else {
                close()
            }
        default:
            super.keyDown(with: event)
        }
    }

    func updateProcessingState(_ state: ProcessingState) {
        contentViewModel.processingState = state
    }

    func showResult(_ text: String, isInClipboard: Bool = false) {
        contentViewModel.showResult(text, isInClipboard: isInClipboard)
    }

    func updateActionsIfIdle(_ actions: [SuggestedAction]) {
        contentViewModel.updateActionsIfIdle(actions)
    }
}

@MainActor
class FloatingPanelViewModel: ObservableObject {
    let context: ClipboardContext
    private let skillLoader: SkillLoader
    private let executor: ToolExecutor
    private let classifier = ClipboardClassifier()
    private static let executionTimeoutNanoseconds: UInt64 = 30_000_000_000
    private static let followUpExcluded: Set<String> = [
        "open-file", "reveal-in-finder", "reveal-path", "open-terminal", "read-article",
        "html-to-markdown", "smart-markdown"
    ]

    @Published var actions: [SuggestedAction]
    /// The always-focused freeform ask text at the top of the trigger state.
    @Published var askText: String = "" {
        didSet {
            // Typing returns focus to the box: the shortcut highlight only
            // reappears once the user arrows back into the list.
            if !askText.isEmpty { isListFocused = false }
        }
    }
    /// Whether the user has arrowed into the shortcut list. While `false` no row
    /// is highlighted (the ask field owns input); Return then runs freeform.
    @Published var isListFocused: Bool = false
    @Published var selectedIndex: Int = 0
    @Published var processingState: ProcessingState = .idle
    @Published var executedAction: SuggestedAction?
    @Published var resultText: String?
    @Published var isResultInClipboard: Bool = false
    @Published var isGenerating: Bool = false
    @Published var followUpActions: [SuggestedAction] = []
    @Published var pipelineSteps: [PipelineStep] = []
    @Published var selectedFollowUpIndex: Int = 0
    private var activeExecutionID: UUID?
    private var cancelGeneration: (() -> Void)?

    var onActionStarted: (() -> Void)?
    var requestClose: (() -> Void)?

    init(context: ClipboardContext, actions: [SuggestedAction], skillLoader: SkillLoader, executor: ToolExecutor) {
        self.context = context
        self.actions = actions
        self.skillLoader = skillLoader
        self.executor = executor
    }

    var contentTypeIcon: String {
        switch context.snapshot.kind {
        case .url: return "link"
        case .fileURLs: return "folder"
        case .image: return "photo"
        case .plainText: return "text.quote"
        case .richText: return "doc.richtext"
        case .unknown: return "doc"
        }
    }

    var contentTypeDescription: String {
        let topLevelType = context.snapshot.primaryContentLabel

        let tags = context.snapshot.detectedEntities
            .map(\.displayName)
            .filter { !$0.isEmpty }

        let base = tags.isEmpty ? topLevelType : "\(topLevelType) • \(tags.joined(separator: ", "))"

        switch context.snapshot.kind {
        case .plainText, .richText:
            let count = context.snapshot.plainText?.count ?? 0
            return "\(base) (\(count) chars)"
        case .fileURLs:
            let count = context.snapshot.fileURLs?.count ?? 0
            return count > 1 ? "\(base) (\(count))" : base
        default:
            return base
        }
    }

    /// Short content-type label shown in the panel header (e.g. "Rich Text").
    var contentTypeLabel: String {
        context.snapshot.primaryContentLabel
    }

    /// First detected entity, shown as an accent-subtle chip in the header
    /// (e.g. "Email Draft"). `nil` when nothing was detected.
    var entityChipLabel: String? {
        let name = context.snapshot.detectedEntities.first?.displayName ?? ""
        return name.isEmpty ? nil : name
    }

    /// Mono "N chars" / file count metadata for the header, or `nil` when the
    /// content kind has no meaningful count (e.g. an image or URL).
    var contentMeasureLabel: String? {
        switch context.snapshot.kind {
        case .plainText, .richText:
            let count = context.snapshot.plainText?.count ?? 0
            return "\(count) chars"
        case .fileURLs:
            let count = context.snapshot.fileURLs?.count ?? 0
            return count > 1 ? "\(count) files" : nil
        default:
            return nil
        }
    }

    func updateActionsIfIdle(_ newActions: [SuggestedAction]) {
        guard processingState == .idle, !newActions.isEmpty else { return }
        actions = newActions
        selectedIndex = min(selectedIndex, max(newActions.count - 1, 0))
    }

    func selectPrevious() {
        if processingState == .completed, !followUpActions.isEmpty {
            selectedFollowUpIndex = (selectedFollowUpIndex - 1 + followUpActions.count) % followUpActions.count
        } else if processingState == .idle, !actions.isEmpty {
            if !isListFocused {
                // First arrow into the list highlights the last row (up).
                isListFocused = true
                selectedIndex = actions.count - 1
            } else {
                selectedIndex = (selectedIndex - 1 + actions.count) % actions.count
            }
        }
    }

    func selectNext() {
        if processingState == .completed, !followUpActions.isEmpty {
            selectedFollowUpIndex = (selectedFollowUpIndex + 1) % followUpActions.count
        } else if processingState == .idle, !actions.isEmpty {
            if !isListFocused {
                // First arrow into the list highlights the first row (down).
                isListFocused = true
                selectedIndex = 0
            } else {
                selectedIndex = (selectedIndex + 1) % actions.count
            }
        }
    }

    func executeSelected() {
        // If follow-ups are showing, execute the selected follow-up
        if processingState == .completed, !followUpActions.isEmpty, selectedFollowUpIndex < followUpActions.count {
            executeFollowUp(followUpActions[selectedFollowUpIndex])
            return
        }
        guard processingState == .idle, selectedIndex < actions.count else { return }
        run(actions[selectedIndex])
    }

    /// Return handling for the trigger state, in priority order:
    /// 1) an actively highlighted shortcut → run it,
    /// 2) a non-empty ask box → run the freeform ask,
    /// 3) an empty box → run the top-ranked action.
    func handleTriggerReturn() {
        guard processingState == .idle else { return }
        if isListFocused, selectedIndex < actions.count {
            run(actions[selectedIndex])
            return
        }
        let ask = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ask.isEmpty {
            submitFreeform()
            return
        }
        guard !actions.isEmpty else { return }
        selectedIndex = 0
        run(actions[0])
    }

    /// Builds and runs the freeform ask currently typed in the box.
    func submitFreeform() {
        let ask = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty, processingState == .idle else { return }
        run(makeFreeformAction(ask: ask))
    }

    /// Synthesizes a `SuggestedAction` for a freeform ask. Routes to a tuned
    /// skill when the ask clearly matches one (skill-grade quality); otherwise
    /// runs the generic wrapped `.llmPrompt` over the preprocessed clipboard.
    func makeFreeformAction(ask: String) -> SuggestedAction {
        if let routed = skillLoader.freeformSkillMatch(for: ask, context: context, executor: executor) {
            return routed
        }

        let systemPrompt = Self.freeformSystemPrompt(ask: ask)
        let clipboardText = ClipboardTextPreprocessor.bestLLMInput(from: context.snapshot)
            ?? context.snapshot.plainText
            ?? context.snapshot.url?.absoluteString
            ?? ""
        let ctx = context

        return SuggestedAction(
            skillId: "freeform",
            title: ask,
            subtitle: "Freeform ask",
            systemImage: "sparkles"
        ) { [weak executor] completion, onToken in
            guard let executor else { return nil }
            return executor.runFreeformPrompt(
                prompt: clipboardText,
                systemPrompt: systemPrompt,
                temperature: 0.2,
                context: ctx,
                completion: completion,
                onToken: onToken
            )
        }
    }

    /// Fixed wrapper constraining the small local model around the user's ask.
    static func freeformSystemPrompt(ask: String) -> String {
        """
        You act on the user's copied text below. Do exactly what the user asks.
        Rules:
        - Output only the result — no preamble, no explanation, no "Sure" / "Here is".
        - Preserve formatting, code, URLs, names, and the original language unless asked otherwise.
        - Do not invent facts, quotes, numbers, or details not present in the text.
        - If the request cannot be done from the text, say so in one short sentence.

        User request: \(ask)
        """
    }

    private func run(_ action: SuggestedAction) {
        let executionID = UUID()
        activeExecutionID = executionID
        resultText = nil
        isResultInClipboard = false
        isGenerating = false
        executedAction = action
        processingState = .processing("Running \(action.title)…")

        UsageHistory.shared.record(
            skillId: action.skillId,
            contentKind: context.snapshot.kind,
            sourceContext: context.sourceAppContext
        )

        onActionStarted?()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.executionTimeoutNanoseconds)
            guard let self else { return }
            guard self.activeExecutionID == executionID, self.processingState != .completed else { return }
            self.stopGeneration()
            self.showResult("Failed: Action timed out", isInClipboard: false)
        }

        cancelGeneration = action.perform(
            { [weak self] text, isInClipboard in
                guard let self, self.activeExecutionID == executionID else { return }
                self.showResult(text, isInClipboard: isInClipboard)
            },
            { [weak self] token in
                guard let self, self.activeExecutionID == executionID else { return }
                if !self.isGenerating {
                    self.isGenerating = true
                    self.processingState = .completed
                }
                self.resultText = (self.resultText ?? "") + token
            }
        )
    }

    func showResult(_ text: String, isInClipboard: Bool) {
        activeExecutionID = nil
        cancelGeneration = nil
        isGenerating = false
        if text.isEmpty, isInClipboard {
            resultText = NSPasteboard.general.string(forType: .string)
        } else {
            resultText = text
        }
        isResultInClipboard = isInClipboard
        processingState = .completed

        // Log to daily memory
        let pipelineNames = pipelineSteps.map(\.action.title)
        let appName = context.copyEvent?.appName
            ?? (context.snapshot.kind == .fileURLs ? "Finder" : nil)
        SkillMemory.shared.logAction(
            skillId: executedAction?.skillId ?? "",
            skillName: executedAction?.title ?? "",
            sourceApp: context.sourceAppContext,
            appName: appName,
            pipelineHistory: pipelineNames
        )

        loadFollowUpActions()
    }

    func executeFollowUp(_ action: SuggestedAction) {
        guard processingState == .completed else { return }
        let previousResult = resultText ?? ""

        // Push current action+result to pipeline history
        if let current = executedAction, !previousResult.isEmpty {
            pipelineSteps.append(PipelineStep(action: current, resultText: previousResult))
        }

        let executionID = UUID()
        activeExecutionID = executionID
        resultText = nil
        isResultInClipboard = false
        isGenerating = false
        executedAction = action
        followUpActions = []
        selectedFollowUpIndex = 0
        processingState = .processing("Running \(action.title)…")

        // Write previous result to clipboard so the skill reads it as input
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previousResult, forType: .string)

        UsageHistory.shared.record(
            skillId: action.skillId,
            contentKind: .plainText,
            sourceContext: context.sourceAppContext
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.executionTimeoutNanoseconds)
            guard let self, self.activeExecutionID == executionID, self.processingState != .completed else { return }
            self.stopGeneration()
            self.showResult("Failed: Action timed out", isInClipboard: false)
        }

        cancelGeneration = action.perform(
            { [weak self] text, isInClipboard in
                guard let self, self.activeExecutionID == executionID else { return }
                self.showResult(text, isInClipboard: isInClipboard)
            },
            { [weak self] token in
                guard let self, self.activeExecutionID == executionID else { return }
                if !self.isGenerating {
                    self.isGenerating = true
                    self.processingState = .completed
                }
                self.resultText = (self.resultText ?? "") + token
            }
        )
    }

    private func loadFollowUpActions() {
        guard let text = resultText, !text.isEmpty else {
            followUpActions = []
            return
        }

        // Build the available skills pool (excluding used + irrelevant)
        let resultContext = ClipboardContext.fromResultText(
            text,
            classifier: classifier,
            copyEvent: context.copyEvent
        )
        let matched = skillLoader.matchingActions(
            for: .plainText,
            sourceContext: resultContext.sourceAppContext,
            entities: resultContext.snapshot.detectedEntities,
            context: resultContext,
            executor: executor
        )

        var excluded = Self.followUpExcluded
        if let currentSkill = executedAction?.skillId {
            excluded.insert(currentSkill)
        }
        for step in pipelineSteps {
            excluded.insert(step.action.skillId)
        }
        let candidates = matched.filter { !excluded.contains($0.skillId) }

        // Immediate: show heuristic results while LLM thinks
        followUpActions = Array(candidates.prefix(3))

        // Background: ask LLM to pick smarter follow-ups
        guard LocalLLMService.shared.isReady, candidates.count > 1 else { return }

        let actionName = executedAction?.title ?? ""
        let preview = String(text.prefix(300))
        let availableList = candidates.map { "- \($0.skillId): \($0.title)" }.joined(separator: "\n")
        let memoryContext = SkillMemory.shared.buildContext()

        Task { [weak self] in
            guard let self else { return }
            do {
                let prompt = """
                The user just ran "\(actionName)" and got this result:
                \(preview)

                \(memoryContext.isEmpty ? "" : memoryContext + "\n")
                Available next actions:
                \(availableList)

                Pick 1-3 actions that would produce meaningfully different output. Skip actions that would give the same result. Reply ONLY as a JSON array of action IDs: ["id1", "id2"]
                """

                let response = try await LocalLLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "You pick the most useful next clipboard actions. Reply only with a JSON array of action IDs.",
                    temperature: 0,
                    maxTokens: 50
                )

                // Parse JSON array from response
                let suggested = self.parseSuggestedIds(from: response)

                await MainActor.run {
                    guard self.processingState == .completed else { return }
                    if !suggested.isEmpty {
                        var reordered = suggested.compactMap { id in
                            candidates.first { $0.skillId == id }
                        }
                        for candidate in self.followUpActions where !reordered.contains(where: { $0.skillId == candidate.skillId }) {
                            reordered.append(candidate)
                        }
                        if !reordered.isEmpty {
                            self.followUpActions = Array(reordered.prefix(3))
                            self.selectedFollowUpIndex = min(self.selectedFollowUpIndex, max(self.followUpActions.count - 1, 0))
                        }
                    }
                }
            } catch {
                // LLM failed — keep heuristic results
            }
        }
    }

    private nonisolated func parseSuggestedIds(from response: String) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find JSON array in response
        guard let start = trimmed.firstIndex(of: "["),
              let end = trimmed[start...].lastIndex(of: "]") else {
            return []
        }
        let jsonString = String(trimmed[start...end])
        guard let data = jsonString.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    func stopGeneration() {
        guard isGenerating || cancelGeneration != nil else { return }
        cancelGeneration?()
        cancelGeneration = nil
        isGenerating = false
        activeExecutionID = nil
        if let text = resultText, !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            isResultInClipboard = true
        }
        processingState = .completed
    }

    func resetToActions() {
        stopGeneration()
        activeExecutionID = nil
        cancelGeneration = nil
        isGenerating = false
        executedAction = nil
        resultText = nil
        isResultInClipboard = false
        followUpActions = []
        pipelineSteps = []
        selectedFollowUpIndex = 0
        processingState = .idle
        selectedIndex = 0
        isListFocused = false
        askText = ""
    }
}

struct PipelineStep: Identifiable {
    let id = UUID()
    let action: SuggestedAction
    let resultText: String
    var isExpanded: Bool = false
}

enum ProcessingState: Equatable {
    case idle
    case processing(String)
    case completed

    var description: String {
        switch self {
        case .idle: return ""
        case .processing(let msg): return msg
        case .completed: return "Done"
        }
    }
}

struct FloatingPanelView: View {
    @ObservedObject var viewModel: FloatingPanelViewModel
    @FocusState private var askFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if viewModel.executedAction != nil {
                executedSection
            } else {
                askFieldSection
                panelDivider
                actionsSection
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: CCRadius.panel, style: .continuous)
                .fill(.regularMaterial)
        )
        // Warm glass tint over the material, matching the Foundry panel surface.
        .background(
            RoundedRectangle(cornerRadius: CCRadius.panel, style: .continuous)
                .fill(Color.ccSurface0.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CCRadius.panel, style: .continuous)
                .strokeBorder(Color.ccTextPrimary.opacity(0.10), lineWidth: 1)
        )
        // Inset top highlight — the "inset 0 1px 0 rgba(255,255,255,0.6)" edge.
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: CCRadius.panel, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                .mask(
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                )
        }
        // Soft two-layer shadow — mirrors --shadow-panel; the card floats on paper.
        .shadow(color: .black.opacity(0.30), radius: 24, x: 0, y: 14)
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.executedAction != nil)
    }

    // MARK: Ask field (freeform)

    private var askFieldSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ccAccent)
                .frame(width: 18, alignment: .center)

            TextField("Ask anything about this…", text: $viewModel.askText)
                .textFieldStyle(.plain)
                .font(.ccSans(14))
                .foregroundStyle(Color.ccTextPrimary)
                .tint(Color.ccAccent)
                .focused($askFieldFocused)

            if !viewModel.askText.isEmpty {
                KeyHint(text: "↵", filled: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: CCRadius.sm, style: .continuous)
                .fill(Color.ccSurface2)
                .overlay(
                    RoundedRectangle(cornerRadius: CCRadius.sm, style: .continuous)
                        .strokeBorder(
                            askFieldFocused && !viewModel.isListFocused ? Color.ccAccent.opacity(0.55) : Color.ccBorder,
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .onAppear { askFieldFocused = true }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.ccBorder)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 4)
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            // Content-type icon tile
            Image(systemName: viewModel.contentTypeIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ccTextSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: CCRadius.iconTile, style: .continuous)
                        .fill(Color.ccSurface2)
                )

            Text(viewModel.contentTypeLabel)
                .font(.ccSans(13.5))
                .foregroundStyle(Color.ccTextSecondary)
                .lineLimit(1)
                .layoutPriority(1)

            if let entity = viewModel.entityChipLabel {
                Text(entity)
                    .font(.ccMono(10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Color.ccAccentText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: CCRadius.badge, style: .continuous)
                            .fill(Color.ccAccentSoft)
                    )
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 4)

            trailingHeaderContent
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var trailingHeaderContent: some View {
        if viewModel.executedAction != nil {
            // Result / processing states show a machine-voice status pill.
            switch viewModel.processingState {
            case .completed:
                statusPill(text: "Done", color: .ccStatusRunning, pulse: false)
            case .processing:
                statusPill(text: "Working", color: .ccAccent, pulse: true)
            case .idle:
                EmptyView()
            }
        } else if viewModel.processingState == .idle, !viewModel.actions.isEmpty {
            if let measure = viewModel.contentMeasureLabel {
                Text(measure)
                    .font(.ccMono(11.5))
                    .foregroundStyle(Color.ccTextMuted)
                    .fixedSize()
            }
            KeyHint(text: "↑↓")
        }
    }

    private func statusPill(text: String, color: Color, pulse: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier(active: pulse))
            Text(text)
                .font(.ccMono(11.5))
                .foregroundStyle(color)
        }
        .fixedSize()
    }

    // MARK: Actions list (idle)

    private var actionsSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.actions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(
                            action: action,
                            isSelected: viewModel.isListFocused && index == viewModel.selectedIndex,
                            compact: false
                        )
                        .id(index)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.executeSelected()
                        }
                    }
                }
                .padding(2)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 240)
    }

    // MARK: Executed / result

    private var executedSection: some View {
        VStack(spacing: 0) {
            // Pipeline history: action + collapsible result pairs
            ForEach(Array(viewModel.pipelineSteps.indices), id: \.self) { index in
                let step = viewModel.pipelineSteps[index]
                pipelineStepRow(step: step, index: index)
            }

            // Current action
            if let action = viewModel.executedAction {
                currentActionRow(action: action)
            }

            // Current result (processing or completed)
            if viewModel.processingState != .idle {
                currentResultSection
            }

            // Follow-up actions
            if viewModel.processingState == .completed {
                followUpSection
            }
        }
    }

    private func pipelineStepRow(step: PipelineStep, index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: step.action.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.ccTextSecondary)
                    .frame(width: 22, alignment: .center)
                Text(step.action.title)
                    .font(.ccSans(14, weight: .medium))
                    .foregroundStyle(Color.ccTextSecondary)
                Spacer()
                Image(systemName: step.isExpanded ? "minus.circle" : "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ccTextMuted)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ccStatusRunning)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    viewModel.pipelineSteps[index].isExpanded.toggle()
                }
            }

            if step.isExpanded {
                ScrollView {
                    Text(step.resultText)
                        .font(.ccSans(13))
                        .foregroundStyle(Color.ccTextPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 200)
                .background(resultWellBackground)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
    }

    private func currentActionRow(action: SuggestedAction) -> some View {
        HStack(spacing: 11) {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.ccTextSecondary)
                .frame(width: 22, alignment: .center)
            Text(action.title)
                .font(.ccSans(14, weight: .semibold))
                .foregroundStyle(Color.ccTextPrimary)
            Spacer()
            if viewModel.isGenerating {
                Button(action: { viewModel.stopGeneration() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.ccTextSecondary)
                }
                .buttonStyle(.plain)
            } else if case .processing = viewModel.processingState {
                ProgressView()
                    .controlSize(.small)
                    .tint(.ccAccent)
            } else if viewModel.processingState == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.ccStatusRunning)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var currentResultSection: some View {
        VStack(spacing: 0) {
            if case .processing(let message) = viewModel.processingState {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.ccAccent)
                    Text(message)
                        .font(.ccSans(13))
                        .foregroundStyle(Color.ccTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else if let text = viewModel.resultText, !text.isEmpty {
                // Result well: inset surface-2 with a streaming caret.
                ScrollView {
                    HStack(alignment: .bottom, spacing: 0) {
                        Text(text)
                            .font(.ccSans(13))
                            .foregroundStyle(Color.ccTextPrimary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                        if viewModel.isGenerating {
                            StreamingCaret()
                                .padding(.leading, 1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                }
                .frame(maxHeight: 300)
                .background(resultWellBackground)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

                // Copied to clipboard — below the result
                if viewModel.isResultInClipboard, !viewModel.isGenerating {
                    HStack(spacing: 11) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ccTextSecondary)
                            .frame(width: 22, alignment: .center)
                        Text("Copied to clipboard")
                            .font(.ccSans(13.5))
                            .foregroundStyle(Color.ccTextSecondary)
                        Spacer()
                        KeyHint(text: "⌘V", filled: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var resultWellBackground: some View {
        RoundedRectangle(cornerRadius: CCRadius.sm, style: .continuous)
            .fill(Color.ccSurface2)
            .overlay(
                RoundedRectangle(cornerRadius: CCRadius.sm, style: .continuous)
                    .strokeBorder(Color.ccBorder, lineWidth: 1)
            )
    }

    private var followUpSection: some View {
        VStack(spacing: 0) {
            if !viewModel.followUpActions.isEmpty {
                Rectangle()
                    .fill(Color.ccBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                Text("Follow-up actions")
                    .font(.ccMono(10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Color.ccTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                VStack(spacing: 2) {
                    ForEach(Array(viewModel.followUpActions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(action: action, isSelected: index == viewModel.selectedFollowUpIndex, compact: true)
                            .onTapGesture {
                                viewModel.executeFollowUp(action)
                            }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }

            HStack(spacing: 11) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ccTextMuted)
                    .frame(width: 22, alignment: .center)
                Text("Back")
                    .font(.ccSans(13.5))
                    .foregroundStyle(Color.ccTextMuted)
                Spacer()
                KeyHint(text: "esc")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.resetToActions()
            }
        }
    }
}

// MARK: - Reusable pieces

/// A bordered "machine voice" key hint (↑↓, esc, ⌘V).
private struct KeyHint: View {
    let text: String
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.ccMono(12))
            .foregroundStyle(Color.ccTextMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: CCRadius.badge, style: .continuous)
                    .fill(filled ? Color.ccSurface2 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CCRadius.badge, style: .continuous)
                    .strokeBorder(Color.ccBorderStrong, lineWidth: 1)
            )
            .fixedSize()
    }
}

/// The blinking caret that trails streaming result text (step-end, ~1.1s cycle).
private struct StreamingCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.ccAccent)
                .frame(width: 2, height: 15)
                .opacity(on ? 1 : 0)
        }
    }
}

/// Slow "agent alive" pulse for the working status dot.
private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (dimmed ? 0.4 : 1.0) : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

struct ActionRow: View {
    let action: SuggestedAction
    let isSelected: Bool
    /// Compact single-line rows (follow-ups) hide the subtitle.
    var compact: Bool = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isSelected ? Color.white : Color.ccTextSecondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.ccSans(14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.ccTextPrimary)
                if !compact, let subtitle = action.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.ccSans(11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.ccTextMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isSelected {
                Text("↵")
                    .font(.ccMono(12))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: CCRadius.badge, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: CCRadius.sm, style: .continuous)
                .fill(isSelected ? Color.ccAccent : (isHovered ? Color.ccSurface2 : Color.clear))
        )
        // Steel-blue tinted lift under the selected row (mirrors the design shadow).
        .shadow(color: isSelected ? Color.ccAccent.opacity(0.40) : .clear, radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
