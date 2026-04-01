import SwiftUI

@MainActor
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
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
}
