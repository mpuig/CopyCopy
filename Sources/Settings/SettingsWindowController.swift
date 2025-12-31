import Cocoa
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func show(settings: AppSettings, model: AppModel, actionsStore: CustomActionsStore, updater: UpdaterProviding) {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            settings: settings,
            model: model,
            actionsStore: actionsStore,
            updater: updater
        )

        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "CopyCopy Settings"
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.minSize = NSSize(width: 500, height: 400)
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
