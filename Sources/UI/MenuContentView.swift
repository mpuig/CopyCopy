import SwiftUI

@MainActor
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var llmService = LocalLLMService.shared
    let updater: UpdaterProviding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let permissionPromptTitle = model.permissionPromptTitle {
                Button(permissionPromptTitle) {
                    model.resolvePermissionPromptAction()
                }
                .buttonStyle(.plain)
                Divider()
            }

            modelSection

            Divider()

            Button {
                SettingsWindowController.shared.show(
                    settings: settings,
                    model: model,
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

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(downloadedModels) { def in
                Button {
                    settings.llmModel = def.id
                    Task { await LocalLLMService.shared.loadModel() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: llmService.loadedModelId == def.id ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(llmService.loadedModelId == def.id ? .green : .secondary)
                        Text(def.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if downloadedModels.isEmpty {
                Text("No models downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var downloadedModels: [ModelDefinition] {
        ModelDefinition.all.filter(\.isDownloaded)
    }
}
