import AppKit
import SwiftUI

@MainActor
struct SettingsDebugPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    title: "Status",
                    caption: "Current state of CopyCopy components.")
                {
                    VStack(alignment: .leading, spacing: 8) {
                        statusRow("Accessibility Permission", value: model.hasAccessibilityPermission ? "✅ Granted" : "❌ Not granted")
                        statusRow("Event Tap", value: model.isEventTapRunning ? "✅ Running" : "❌ Stopped")
                        if model.hasAccessibilityPermission && !model.isEventTapRunning {
                            statusRow("Likely Missing", value: "Input Monitoring")
                        }
                        statusRow("Double-copy Threshold", value: "\(Int(settings.doubleCopyThresholdMs))ms")
                    }
                }

                SettingsSection(
                    title: "Clipboard",
                    caption: "Current clipboard state.")
                {
                    VStack(alignment: .leading, spacing: 8) {
                        if let ctx = model.lastClipboardContext {
                            statusRow("Content Type", value: ctx.snapshot.kind.rawValue)
                            statusRow("Summary", value: ctx.snapshot.summary)
                            let entities = ctx.snapshot.detectedEntities.map(\.displayName).joined(separator: ", ")
                            statusRow("Detected Tags", value: entities.isEmpty ? "None" : entities)
                            if let appName = ctx.copyEvent?.appName {
                                statusRow("Source App", value: appName)
                            }
                            statusRow("Source Context", value: String(describing: ctx.sourceAppContext))
                        } else {
                            Text("No clipboard content captured yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsSection(
                    title: "Actions",
                    caption: "Debug actions for testing.")
                {
                    HStack(spacing: 12) {
                        Button("Trigger Pulse") {
                            model.triggerPulseID = UUID()
                        }
                        .controlSize(.small)

                        Button("Refresh Permissions") {
                            model.refreshPermissions(promptIfNeeded: false)
                        }
                        .controlSize(.small)

                        Button("Open Accessibility Settings") {
                            model.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }

                SettingsSection(
                    title: "App Info",
                    caption: "Build and runtime information.")
                {
                    VStack(alignment: .leading, spacing: 8) {
                        statusRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
                        statusRow("Executable", value: Bundle.main.executableURL?.lastPathComponent ?? "Unknown")
                        statusRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)

                        #if DEBUG
                        statusRow("Build", value: "DEBUG")
                        #else
                        statusRow("Build", value: "RELEASE")
                        #endif
                    }
                }

                SettingsSection {
                    PreferenceToggleRow(
                        title: "Enable Debug Tab",
                        subtitle: "Shows or hides this Debug tab in Settings.",
                        binding: $settings.debugMenuEnabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
