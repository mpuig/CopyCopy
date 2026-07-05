import SwiftUI

/// First-run onboarding that explains the two macOS permissions CopyCopy needs
/// and deep-links the user to the right System Settings panes. Permission state
/// is read live from `AppModel`, so the status indicators update as soon as the
/// user grants access (the model polls on a timer).
@MainActor
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let onFinish: () -> Void

    private var allGranted: Bool {
        model.hasAccessibilityPermission && model.isEventTapRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text("Two permissions to get started")
                    .font(.headline)
                Text("CopyCopy watches for a quick double ⌘C anywhere on your Mac, then shows contextual actions. To detect that gesture system-wide, macOS asks you to grant two permissions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
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
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CCRadius.md, style: .continuous)
                    .fill(Color.ccSurfaceSunken))
            .overlay(
                RoundedRectangle(cornerRadius: CCRadius.md, style: .continuous)
                    .stroke(Color.ccBorder, lineWidth: 1))

            Text("Your clipboard stays on this Mac — CopyCopy never sends it anywhere. You can revisit this any time under Settings › General › Permissions.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(allGranted ? "Done" : "Continue Without Permissions") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.ccAccent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onChange(of: allGranted) { _, granted in
            if granted { finish() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.ccAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to CopyCopy")
                    .font(.title2.weight(.semibold))
                Text("Contextual actions on double ⌘C.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}
