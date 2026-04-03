import SwiftUI

@MainActor
struct SettingsLLMPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var llmService = LocalLLMService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                enableSection

                if settings.llmEnabled {
                    Divider()
                    modelSection
                    Divider()
                    statusSection
                }
            }
            .padding()
        }
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "brain")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Features")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("On-device AI for text transformation, summarization, and smart actions. No data leaves your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var enableSection: some View {
        Toggle("Enable AI Features", isOn: $settings.llmEnabled)
            .toggleStyle(.switch)
            .font(.headline)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model", systemImage: "cpu")
                .font(.headline)

            Picker("", selection: $settings.llmModel) {
                ForEach(ModelDefinition.all) { model in
                    Text("\(model.name) (\(model.sizeLabel))")
                        .tag(model.id)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if settings.llmModel != llmService.loadedModelId ?? "" {
                Button("Load Model") {
                    Task { await LocalLLMService.shared.loadModel() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("Models are downloaded once and cached in ~/.cache/copycopy/models/")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(llmService.isReady ? .green : (llmService.isLoading ? .orange : .gray))
                    .frame(width: 8, height: 8)
                Text(llmService.isReady ? "Ready" : (llmService.isLoading ? "Loading..." : "Not loaded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if llmService.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(llmService.loadingProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if llmService.downloadProgress > 0 && llmService.downloadProgress < 1 {
                    ProgressView(value: llmService.downloadProgress)
                        .progressViewStyle(.linear)
                }
            }

            if let error = llmService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
