import Cocoa
import SwiftUI
import Combine

@MainActor
class FloatingActionPanel: NSPanel {
    private let contentViewModel: FloatingPanelViewModel
    private var cancellables = Set<AnyCancellable>()
    
    init(context: ClipboardContext, actions: [SuggestedAction]) {
        self.contentViewModel = FloatingPanelViewModel(context: context, actions: actions)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupContent()
        positionWindowNearCursor()
        
        // Setup close callback
        contentViewModel.requestClose = { [weak self] in
            self?.close()
        }
    }
    
    private func setupWindow() {
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true
    }
    
    private func setupContent() {
        let hostingView = NSHostingView(rootView: FloatingPanelView(viewModel: contentViewModel))
        contentView = hostingView
    }
    
    private func positionWindowNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        
        guard let screen = screen else { return }
        
        let panelSize = CGSize(width: 400, height: min(300, 100 + contentViewModel.actions.count * 50))
        var origin = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height - 20
        )
        
        // Ensure window stays on screen
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
    
    func show() {
        makeKeyAndOrderFront(nil)
        becomeFirstResponder()
        
        // Auto-close after 30 seconds of inactivity
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.contentViewModel.processingState == .idle {
                self?.close()
            }
        }
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            contentViewModel.selectPrevious()
        case 125: // Down arrow
            contentViewModel.selectNext()
        case 36: // Return/Enter
            contentViewModel.executeSelected()
        case 53: // Escape
            close()
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
    @Published var actions: [SuggestedAction]
    @Published var selectedIndex: Int = 0
    @Published var processingState: ProcessingState = .idle
    @Published var executedAction: SuggestedAction?
    @Published var resultText: String?
    @Published var isResultInClipboard: Bool = false

    init(context: ClipboardContext, actions: [SuggestedAction]) {
        self.context = context
        self.actions = actions
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
        switch context.snapshot.kind {
        case .url: return "URL"
        case .fileURLs: return "\(context.snapshot.fileURLs?.count ?? 0) files"
        case .image: return "Image"
        case .plainText: return "Text (\(context.snapshot.plainText?.count ?? 0) chars)"
        case .richText: return "Rich Text"
        case .unknown: return "Unknown"
        }
    }

    func selectPrevious() {
        guard processingState == .idle else { return }
        selectedIndex = (selectedIndex - 1 + actions.count) % actions.count
    }

    func selectNext() {
        guard processingState == .idle else { return }
        selectedIndex = (selectedIndex + 1) % actions.count
    }

    func executeSelected() {
        guard processingState == .idle, selectedIndex < actions.count else { return }
        let action = actions[selectedIndex]
        executedAction = action
        processingState = .processing("Running…")
        action.perform { [weak self] text, isInClipboard in
            self?.showResult(text, isInClipboard: isInClipboard)
        }
    }

    func showResult(_ text: String, isInClipboard: Bool) {
        resultText = text
        isResultInClipboard = isInClipboard
        processingState = .completed
    }

    var requestClose: (() -> Void)?
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

            Divider()

            if viewModel.executedAction != nil {
                executedSection
            } else {
                actionsSection
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .animation(.easeInOut(duration: 0.2), value: viewModel.executedAction != nil)
    }
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.contentTypeIcon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text(viewModel.contentTypeDescription)
                .font(.body)
                .fontWeight(.medium)
            Spacer()
            if viewModel.processingState == .idle, !viewModel.actions.isEmpty {
                Text("↑↓")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
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
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 200)
    }
    
    private var executedSection: some View {
        VStack(spacing: 0) {
            if let action = viewModel.executedAction {
                HStack(spacing: 10) {
                    Image(systemName: action.systemImage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                    Text(action.title)
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    if case .processing = viewModel.processingState {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.processingState == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if viewModel.processingState == .completed {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let text = viewModel.resultText, !text.isEmpty {
                        ScrollView {
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }

                    if viewModel.isResultInClipboard {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Copied to clipboard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("⌘V")
                                .font(.caption)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.separatorColor).opacity(0.3))
                                .cornerRadius(3)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

struct ActionRow: View {
    let action: SuggestedAction
    let isSelected: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20, alignment: .center)

            Text(action.title)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}
