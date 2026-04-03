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

                    if !settings.useLocalLLM {
                        Divider()
                        apiKeySection
                    }
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
                Text("On-device AI for text transformation, summarization, and smart actions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable AI Features", isOn: $settings.llmEnabled)
                .toggleStyle(.switch)
                .font(.headline)

            Toggle("Use Local Model (on-device, private)", isOn: $settings.useLocalLLM)
                .toggleStyle(.switch)
                .disabled(!settings.llmEnabled)

            if settings.useLocalLLM {
                Text("All processing happens on your Mac. No data leaves your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model", systemImage: "cpu")
                .font(.headline)

            Picker("", selection: $settings.llmModel) {
                Text("LFM 2.5 1.2B Instruct — Recommended (~1.2 GB)")
                    .tag("LiquidAI/LFM2.5-1.2B-Instruct-MLX-8bit")
                Text("LFM 2.5 350M — Faster, less accurate (~350 MB)")
                    .tag("mlx-community/LFM2.5-350M-8bit")
                Text("Gemma 4 E4B Instruct — Most capable (~9 GB)")
                    .tag("unsloth/gemma-4-E4B-it-MLX-8bit")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Models are downloaded to ~/.cache/huggingface/ and shared with other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.llmModel != llmService.loadedModelId ?? "" {
                Button("Load Model") {
                    Task {
                        await LocalLLMService.shared.loadModel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Status", systemImage: "circle.fill")
                .font(.headline)
                .foregroundStyle(llmService.isReady ? .green : (llmService.isLoading ? .orange : .secondary))

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
            } else if llmService.isReady {
                Text("Model loaded and ready")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if let error = llmService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Model not loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("HuggingFace API Key", systemImage: "key")
                .font(.headline)

            SecureField("Enter your HuggingFace API key", text: $settings.llmApiKey)
                .textFieldStyle(.roundedBorder)

            if settings.llmApiKey.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("API key required for remote AI features")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
