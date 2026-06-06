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
            if !downloadingModels.isEmpty {
                ForEach(downloadingModels) { def in
                    downloadStatusRow(def)
                }
            }

            ForEach(downloadedModels) { def in
                Button {
                    settings.llmModel = def.id
                    Task { await LocalLLMService.shared.loadModel() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: llmService.loadedModelId == def.id ? "circle.inset.filled" : "circle")
                            .font(.caption)
                            .foregroundStyle(llmService.loadedModelId == def.id ? .primary : .secondary)
                        Text(def.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if downloadedModels.isEmpty && downloadingModels.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI model not downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Open Settings to download Gemma 4 E2B.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func downloadStatusRow(_ def: ModelDefinition) -> some View {
        let progress = llmService.downloadingModels[def.id] ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading \(def.name)…")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text("Keep CopyCopy open while the local AI model downloads.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private var downloadedModels: [ModelDefinition] {
        ModelDefinition.all.filter(\.isDownloaded)
    }

    private var downloadingModels: [ModelDefinition] {
        ModelDefinition.all.filter { llmService.downloadingModels[$0.id] != nil }
    }
}
