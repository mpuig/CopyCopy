import SwiftUI

@MainActor
struct SettingsActionsPane: View {
    @ObservedObject var actionsStore: CustomActionsStore
    @State private var selectedAction: CustomAction?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("Actions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("Actions appear in the menu when you double ⌘C. Enable, disable, or create custom actions. Use {text} as a placeholder for the copied content.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if actionsStore.actions.isEmpty {
                    emptyState
                } else {
                    actionsList
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    HStack {
                        Button {
                            let newAction = CustomAction()
                            ActionEditorWindowController.shared.show(
                                action: newAction,
                                isNew: true,
                                onSave: { savedAction in
                                    actionsStore.addAction(savedAction)
                                },
                                onCancel: {}
                            )
                        } label: {
                            Label("Add Action", systemImage: "plus")
                        }

                        Spacer()

                        if !actionsStore.actions.isEmpty {
                            Button(role: .destructive) {
                                if let selected = selectedAction, !selected.isBuiltIn {
                                    actionsStore.removeAction(selected)
                                    selectedAction = nil
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .disabled(selectedAction == nil || selectedAction?.isBuiltIn == true)
                        }

                        Button {
                            actionsStore.resetToDefaults()
                            selectedAction = nil
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No custom actions yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Add actions to quickly perform tasks with copied text.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actionsStore.actions) { action in
                ActionRowView(
                    action: action,
                    isSelected: selectedAction?.id == action.id,
                    onSelect: { selectedAction = action },
                    onEdit: {
                        ActionEditorWindowController.shared.show(
                            action: action,
                            isNew: false,
                            onSave: { savedAction in
                                actionsStore.updateAction(savedAction)
                            },
                            onCancel: {}
                        )
                    },
                    onDuplicate: {
                        var duplicate = action
                        duplicate.id = UUID()
                        duplicate.name = "\(action.name) Copy"
                        actionsStore.addAction(duplicate)
                    },
                    onDelete: {
                        actionsStore.removeAction(action)
                        if selectedAction?.id == action.id {
                            selectedAction = nil
                        }
                    }
                )
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct ActionRowView: View {
    let action: CustomAction
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(action.isEnabled ? .primary : .tertiary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.name)
                        .font(.body)
                        .foregroundStyle(action.isEnabled ? .primary : .secondary)

                    if action.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundStyle(.secondary)
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 6) {
                    if action.contentFilter != .any {
                        Text(action.contentFilter.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .cornerRadius(4)
                    }

                    if action.sourceFilter != .any {
                        Text(action.sourceFilter.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .cornerRadius(4)
                    }

                    if action.entityFilter != .any {
                        Text(action.entityFilter.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            if !action.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
            }

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Edit action")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onEdit()
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Edit") { onEdit() }
            Button("Duplicate") { onDuplicate() }
            if !action.isBuiltIn {
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}
