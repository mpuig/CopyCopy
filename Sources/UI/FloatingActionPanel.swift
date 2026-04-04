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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
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

            if event.keyCode == 53 {
                if self.contentViewModel.isGenerating {
                    self.contentViewModel.stopGeneration()
                } else if self.contentViewModel.executedAction != nil {
                    self.contentViewModel.resetToActions()
                } else {
                    self.close()
                }
                return nil
            }

            return event
        }
    }

    private func positionWindowNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        guard let screen = screen else { return }

        let panelSize = CGSize(width: 400, height: desiredPanelHeight())
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
        if contentViewModel.executedAction == nil {
            return min(300, 100 + CGFloat(contentViewModel.actions.count) * 50)
        }

        switch contentViewModel.processingState {
        case .idle:
            return min(300, 100 + CGFloat(contentViewModel.actions.count) * 50)
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
        case 36: contentViewModel.executeSelected()
        case 53:
            if contentViewModel.isGenerating {
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
}

@MainActor
class FloatingPanelViewModel: ObservableObject {
    let context: ClipboardContext
    private let skillLoader: SkillLoader
    private let executor: ToolExecutor
    private let classifier = ClipboardClassifier()
    private static let executionTimeoutNanoseconds: UInt64 = 30_000_000_000
    private static let followUpExcluded: Set<String> = [
        "open-file", "reveal-in-finder", "reveal-path", "open-terminal", "read-article"
    ]

    @Published var actions: [SuggestedAction]
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

    func selectPrevious() {
        if processingState == .completed, !followUpActions.isEmpty {
            selectedFollowUpIndex = (selectedFollowUpIndex - 1 + followUpActions.count) % followUpActions.count
        } else if processingState == .idle {
            selectedIndex = (selectedIndex - 1 + actions.count) % actions.count
        }
    }

    func selectNext() {
        if processingState == .completed, !followUpActions.isEmpty {
            selectedFollowUpIndex = (selectedFollowUpIndex + 1) % followUpActions.count
        } else if processingState == .idle {
            selectedIndex = (selectedIndex + 1) % actions.count
        }
    }

    func executeSelected() {
        // If follow-ups are showing, execute the selected follow-up
        if processingState == .completed, !followUpActions.isEmpty, selectedFollowUpIndex < followUpActions.count {
            executeFollowUp(followUpActions[selectedFollowUpIndex])
            return
        }
        guard processingState == .idle, selectedIndex < actions.count else { return }
        let action = actions[selectedIndex]
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
            sourceContext: .other
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

        let resultContext = ClipboardContext.fromResultText(text, classifier: classifier)
        let matched = skillLoader.matchingActions(
            for: .plainText,
            sourceContext: .other,
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
        followUpActions = Array(matched.filter { !excluded.contains($0.skillId) }.prefix(4))
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

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if viewModel.executedAction != nil {
                executedSection
            } else {
                actionsSection
            }
        }
        .padding(6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.92))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.executedAction != nil)
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.contentTypeIcon)
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)
            Text(viewModel.contentTypeDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if viewModel.processingState == .idle, !viewModel.actions.isEmpty {
                Text("↑↓")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var actionsSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.actions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(
                            action: action,
                            isSelected: index == viewModel.selectedIndex,
                            index: index
                        )
                        .id(index)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.executeSelected()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private var executedSection: some View {
        ScrollView {
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
        .frame(maxHeight: 500)
    }

    private func pipelineStepRow(step: PipelineStep, index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: step.action.systemImage)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, alignment: .center)
                Text(step.action.title)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green.opacity(0.5))
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
                Text(step.resultText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .padding(.leading, 30)
            }
        }
    }

    private func currentActionRow(action: SuggestedAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text(action.title)
                .font(.body)
            Spacer()
            if viewModel.isGenerating {
                Button(action: { viewModel.stopGeneration() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if case .processing = viewModel.processingState {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.processingState == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var currentResultSection: some View {
        VStack(spacing: 0) {
            if case .processing(let message) = viewModel.processingState {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else if let text = viewModel.resultText, !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .padding(.leading, 20)

                // Copied to clipboard — below the result
                if viewModel.isResultInClipboard, !viewModel.isGenerating {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .center)
                        Text("Copied to clipboard")
                            .font(.body)
                        Spacer()
                        Text("⌘V")
                            .font(.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08))
                            .cornerRadius(4)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var followUpSection: some View {
        VStack(spacing: 0) {
            if !viewModel.followUpActions.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.followUpActions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(action: action, isSelected: index == viewModel.selectedFollowUpIndex, index: index)
                            .onTapGesture {
                                viewModel.executeFollowUp(action)
                            }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                Text("Back")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
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

struct ActionRow: View {
    let action: SuggestedAction
    let isSelected: Bool
    let index: Int
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : .primary)
                if let subtitle = action.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.08) : Color.clear))
        )
        .scaleEffect(isSelected ? 1.0 : (isHovered ? 1.01 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
