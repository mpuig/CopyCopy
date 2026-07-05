import AppKit
import SwiftUI

@MainActor
struct SettingsGeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
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

                permissionsSection

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
                            .foregroundStyle(Color.ccSuccess)
                        let overridden = model.overriddenBuiltInSkillIds.count
                        Text("\(BuiltInSkills.all.count - overridden) built-in skills active")
                    }

                    if !model.overriddenBuiltInSkillIds.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(Color.ccAccent)
                                Text("\(model.overriddenBuiltInSkillIds.count) built-in \(model.overriddenBuiltInSkillIds.count == 1 ? "skill" : "skills") overridden by custom SKILL.md")
                            }
                            Text(model.overriddenBuiltInSkillIds.sorted().joined(separator: ", "))
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 22)
                        }
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

                    ForEach(ModelDefinition.all) { model in
                        modelRow(model)
                    }

                    Text("On-device model for AI actions. No data leaves your Mac.\nModels cached in ~/.cache/huggingface/hub/")
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

    private var permissionsSection: some View {
        SettingsSection(contentSpacing: 12) {
            HStack {
                Text("Permissions")
                    .font(.headline)
                Spacer()
                Button("Re-check") {
                    model.refreshRuntimeAccessStatus()
                }
                .controlSize(.small)
            }

            PermissionStatusRow(
                title: "Accessibility",
                description: "Lets CopyCopy read which app you copied from.",
                isGranted: model.hasAccessibilityPermission,
                openAction: { model.openAccessibilitySettings() })

            PermissionStatusRow(
                title: "Input Monitoring",
                description: "Lets CopyCopy detect the double ⌘C gesture system-wide.",
                isGranted: model.isEventTapRunning,
                openAction: { model.openInputMonitoringSettings() })

            Text("Both are required to detect the double ⌘C gesture. After granting, CopyCopy re-checks automatically.")
                .foregroundStyle(.secondary)
        }
    }

    private func modelRow(_ model: ModelDefinition) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: settings.llmModel == model.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(settings.llmModel == model.id ? Color.ccAccent : .secondary)
                    .onTapGesture {
                        settings.llmModel = model.id
                        if model.isDownloaded && localLLM.loadedModelId != model.id {
                            Task { await LocalLLMService.shared.loadModel() }
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .fontWeight(settings.llmModel == model.id ? .medium : .regular)
                    Text(model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if localLLM.loadedModelId == model.id {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.ccSuccess)
                } else if localLLM.downloadingModels[model.id] != nil {
                    ProgressView()
                        .controlSize(.small)
                } else if model.isDownloaded {
                    Button("Load") {
                        settings.llmModel = model.id
                        Task { await LocalLLMService.shared.loadModel() }
                    }
                    .controlSize(.small)
                } else {
                    Button("Download") {
                        Task {
                            await LocalLLMService.shared.downloadModel(model)
                        }
                    }
                    .controlSize(.small)
                }
            }

            if let progress = localLLM.downloadingModels[model.id] {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
