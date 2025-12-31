import AppKit
import SwiftUI

@MainActor
struct ActionEditorView: View {
    @State private var action: CustomAction
    let isNew: Bool
    let onSave: (CustomAction) -> Void
    let onCancel: () -> Void

    init(action: CustomAction, isNew: Bool, onSave: @escaping (CustomAction) -> Void, onCancel: @escaping () -> Void) {
        self._action = State(initialValue: action)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isValid: Bool {
        let hasName = !action.name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasTemplate = !action.template.trimmingCharacters(in: .whitespaces).isEmpty
        return hasName && (hasTemplate || !action.actionType.requiresTemplate)
    }

    private var editableActionTypes: [ActionType] {
        [.openURL, .shellCommand, .openApp]
    }

    private var showEntityFilter: Bool {
        action.contentFilter == .text || action.contentFilter == .any
    }

    var body: some View {
        VStack(spacing: 0) {
            formContent
            Divider()
            footer
        }
        .frame(width: 560, height: 540)
        .onChange(of: action.contentFilter) { _, newValue in
            if newValue != .text && newValue != .any {
                action.entityFilter = .any
            }
        }
        .onChange(of: action.actionType) { _, newValue in
            action.systemImage = newValue.systemImage
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nameSection
                ifSection
                thenSection
                enabledSection
            }
            .padding()
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Action name", text: $action.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
        }
    }

    // MARK: - IF Section

    private var ifSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("IF", systemImage: "questionmark.diamond")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                conditionRow("Content is", width: 100) {
                    Picker("Content", selection: $action.contentFilter) {
                        ForEach(ContentTypeFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .labelsHidden()
                }

                conditionRow("Copied from", width: 100) {
                    Picker("Source", selection: $action.sourceFilter) {
                        ForEach(SourceContextFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .labelsHidden()
                }

                if showEntityFilter {
                    conditionRow("Detected as", width: 100) {
                        Picker("Entity", selection: $action.entityFilter) {
                            ForEach(EntityFilter.allCases) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func conditionRow<Content: View>(_ label: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .leading)
            content()
            Spacer()
        }
    }

    // MARK: - THEN Section

    private var thenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("THEN", systemImage: "arrow.right.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 12) {
                actionTypePicker

                if action.actionType.requiresTemplate {
                    templateEditor
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var actionTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if action.isBuiltIn && !editableActionTypes.contains(action.actionType) {
                HStack {
                    Label(action.actionType.displayName, systemImage: action.actionType.systemImage)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .cornerRadius(6)
                    Spacer()
                }
            } else {
                Picker("Action", selection: $action.actionType) {
                    ForEach(editableActionTypes) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Text(actionTypeDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var actionTypeDescription: String {
        switch action.actionType {
        case .openURL:
            return "Opens a URL in your default browser."
        case .shellCommand:
            return "Runs a shell command in the background."
        case .openApp:
            return "Opens an app and pastes the text."
        case .revealInFinder:
            return "Reveals copied files in Finder."
        case .openFile:
            return "Opens the copied file with its default app."
        case .copyToClipboard:
            return "Copies processed text to the clipboard."
        case .saveImage:
            return "Saves clipboard image as PNG."
        case .saveTempFile:
            return "Saves text to a temporary file and opens it."
        case .stripANSI:
            return "Removes ANSI color codes from terminal output."
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(templateLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if action.actionType == .openApp {
                appPicker
            }

            TextEditor(text: $action.template)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            quickExamples

            variablesHelp
        }
    }

    private var templateLabel: String {
        switch action.actionType {
        case .openURL: return "URL Template"
        case .shellCommand: return "Command"
        case .openApp: return "Text to Paste"
        case .copyToClipboard: return "Text Template"
        case .revealInFinder, .openFile, .saveImage, .saveTempFile, .stripANSI:
            return "Template"
        }
    }

    @ViewBuilder
    private var appPicker: some View {
        HStack {
            Text("App:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("App", selection: appBinding) {
                Text("ChatGPT").tag("ChatGPT")
                Text("Claude").tag("Claude")
                Text("Other").tag("Other")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            Spacer()
        }
    }

    private var appBinding: Binding<String> {
        Binding(
            get: {
                if action.template.lowercased().contains("chatgpt") || action.template.isEmpty {
                    return "ChatGPT"
                } else if action.template.lowercased().contains("claude") {
                    return "Claude"
                }
                return "Other"
            },
            set: { _ in }
        )
    }

    private var quickExamples: some View {
        HStack(spacing: 6) {
            Text("Examples:")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Google") {
                action.template = "https://www.google.com/search?q={text:encoded}"
                action.actionType = .openURL
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button("Translate") {
                action.template = "https://translate.google.com/?text={text:encoded}"
                action.actionType = .openURL
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button("ChatGPT") {
                action.template = "Summarize: {text}"
                action.actionType = .openApp
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button("Summarize") {
                action.template = "npx -y @steipete/summarize \"{text}\""
                action.actionType = .shellCommand
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Spacer()
        }
    }

    private var variablesHelp: some View {
        HStack(spacing: 4) {
            Text("Variables:")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("{text}  {text:encoded}  {text:trimmed}  {charcount}  {linecount}")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: true, vertical: false)

            Spacer()
        }
    }

    // MARK: - Enabled Section

    private var enabledSection: some View {
        Toggle("Enabled", isOn: $action.isEnabled)
            .toggleStyle(.checkbox)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button("Save") {
                action.systemImage = action.actionType.systemImage
                onSave(action)
            }
            .keyboardShortcut(.return)
            .disabled(!isValid)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
