import AppKit
import SwiftUI

@MainActor
struct SettingsGeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var localLLM = LocalLLMService.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("System")
                        .font(.headline)

                    PreferenceToggleRow(
                        title: "Start at Login",
                        subtitle: "Automatically opens CopyCopy when you start your Mac.",
                        binding: $settings.launchAtLogin)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("Behavior")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Double-copy threshold: \(Int(settings.doubleCopyThresholdMs))ms")
                        Slider(value: $settings.doubleCopyThresholdMs, in: 150...500, step: 10)
                        Text("Time window to detect double ⌘C. Lower = faster, higher = more forgiving.")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("Skills")
                        .font(.headline)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(BuiltInSkills.all.count) built-in skills active")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text("~/.copycopy/skills/")
                            .font(.body.monospaced())
                        Spacer()
                        Button("Open") {
                            let url = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".copycopy/skills")
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    }
                    Text("Add or override skills by placing a SKILL.md in a subdirectory.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("AI Model")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Image(systemName: modelStatusIcon)
                            .foregroundStyle(modelStatusColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LFM 2.5 (350M)")
                            Text(modelStatusText)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !localLLM.isReady && !localLLM.isLoading {
                            Button("Download") {
                                Task { await LocalLLMService.shared.loadModel() }
                            }
                            .controlSize(.small)
                        }
                    }

                    if localLLM.isLoading {
                        ProgressView(value: localLLM.downloadProgress)
                            .progressViewStyle(.linear)
                        Text(localLLM.loadingProgress)
                            .foregroundStyle(.secondary)
                    }

                    Text("On-device model for prompt-based actions (summarize, translate). No data leaves your Mac.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    HStack {
                        Spacer()
                        Button("Quit CopyCopy") { NSApp.terminate(nil) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var modelStatusIcon: String {
        if localLLM.isReady { return "checkmark.circle.fill" }
        if localLLM.isLoading { return "arrow.down.circle" }
        if localLLM.errorMessage != nil { return "exclamationmark.triangle" }
        return "arrow.down.circle.dotted"
    }

    private var modelStatusColor: Color {
        if localLLM.isReady { return .green }
        if localLLM.errorMessage != nil { return .orange }
        return .secondary
    }

    private var modelStatusText: String {
        if localLLM.isReady { return "Ready" }
        if localLLM.isLoading { return localLLM.loadingProgress }
        if let error = localLLM.errorMessage { return error }
        return "Not downloaded (~77 MB)"
    }
}
