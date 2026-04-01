import SwiftUI

@MainActor
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var actionsStore: CustomActionsStore
    @ObservedObject var localLLM = LocalLLMService.shared
    let updater: UpdaterProviding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.hasAccessibilityPermission {
                accessibilityCallout
                Divider()
            }

            headerSection

            if !model.suggestedActions.isEmpty {
                Divider()
                actionsSection
            }

            Divider()

            settingsSection
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var accessibilityCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Permissions Required", systemImage: "lock.shield")
                .font(.headline)

            Text("CopyCopy needs Accessibility permission to detect ⌘C.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Open Settings…") {
                    model.openAccessibilitySettings()
                }
                Button("Re-check") {
                    model.refreshPermissions(promptIfNeeded: false)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show download progress if model is loading
            if localLLM.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(localLLM.loadingProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let context = model.lastClipboardContext {
                HStack(spacing: 6) {
                    Image(systemName: iconForKind(context.snapshot.kind))
                        .foregroundStyle(.secondary)
                    Text(context.snapshot.summary)
                        .font(.caption)
                        .lineLimit(2)
                }

                if let appName = context.copyEvent?.appName {
                    HStack(spacing: 4) {
                        if let pid = context.copyEvent?.pid,
                           let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 12, height: 12)
                        }
                        Text("from \(appName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Copy something, then double ⌘C.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        ForEach(model.suggestedActions) { action in
            Button {
                action.perform()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                        if let subtitle = action.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: action.systemImage)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if updater.isAvailable, updater.updateStatus.isUpdateReady {
                Button("Update ready, restart now?") {
                    updater.checkForUpdates(nil)
                }
                .buttonStyle(.plain)
            }

            Button {
                SettingsWindowController.shared.show(
                    settings: settings,
                    model: model,
                    actionsStore: actionsStore,
                    updater: updater
                )
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                model.showAbout()
            } label: {
                Label("About CopyCopy", systemImage: "info.circle")
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func iconForKind(_ kind: ClipboardContentKind) -> String {
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
