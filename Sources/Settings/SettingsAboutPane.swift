import AppKit
import SwiftUI

@MainActor
struct SettingsAboutPane: View {
    let updater: UpdaterProviding
    @State private var iconHover = false
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @State private var didLoadUpdaterState = false

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CopyCopyBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private var gitCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "CopyCopyGitCommit") as? String
    }

    var body: some View {
        VStack(spacing: 12) {
            if let image = NSApplication.shared.applicationIconImage {
                Button(action: openProjectHome) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 92, height: 92)
                        .cornerRadius(16)
                        .scaleEffect(iconHover ? 1.05 : 1.0)
                        .shadow(color: iconHover ? Color.ccAccent.opacity(0.25) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        iconHover = hovering
                    }
                }
            }

            VStack(spacing: 2) {
                Text("CopyCopy")
                    .font(.title3).bold()
                Text("Version \(versionString)")
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    HStack(spacing: 4) {
                        Text("Built \(buildTimestamp)")
                        if let gitCommit, gitCommit != "unknown" {
                            Text("(\(gitCommit))")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Text("Double ⌘C for quick clipboard actions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .center, spacing: 10) {
                AboutLinkRow(
                    icon: "chevron.left.slash.chevron.right",
                    title: "GitHub",
                    url: "https://github.com/mpuig/CopyCopy")
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Divider()

            if updater.isAvailable {
                VStack(spacing: 10) {
                    Toggle("Check for updates automatically", isOn: $autoUpdateEnabled)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Check for Updates…") { updater.checkForUpdates(nil) }
                }
            } else {
                Text(updater.unavailableReason ?? "Updates unavailable in this build.")
                    .foregroundStyle(.secondary)
            }

            Text("© 2026. MIT License.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear {
            guard !didLoadUpdaterState else { return }
            updater.automaticallyChecksForUpdates = autoUpdateEnabled
            updater.automaticallyDownloadsUpdates = autoUpdateEnabled
            didLoadUpdaterState = true
        }
        .onChange(of: autoUpdateEnabled) { _, newValue in
            updater.automaticallyChecksForUpdates = newValue
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    private func openProjectHome() {
        guard let url = URL(string: "https://github.com/mpuig/CopyCopy") else { return }
        NSWorkspace.shared.open(url)
    }
}
