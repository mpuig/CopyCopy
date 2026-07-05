import Cocoa
import SwiftUI

/// Presents the first-run permissions onboarding in a standalone window, mirroring
/// `SettingsWindowController`'s single-window lifecycle. Shown once on first launch
/// (until `AppSettings.hasCompletedOnboarding` is set) via `presentIfNeeded`.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    private init() {}

    /// Shows onboarding only if the user has never completed it. No-op otherwise.
    func presentIfNeeded(settings: AppSettings, model: AppModel) {
        guard !settings.hasCompletedOnboarding else { return }
        show(settings: settings, model: model)
    }

    func show(settings: AppSettings, model: AppModel) {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(
            model: model,
            settings: settings,
            onFinish: { [weak self] in self?.close() })

        let hostingController = NSHostingController(rootView: onboardingView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Welcome to CopyCopy"
        newWindow.styleMask = [.titled, .closable]
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
        window = nil
    }
}
