import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    @Published var debugMenuEnabled: Bool {
        didSet {
            UserDefaults.standard.set(debugMenuEnabled, forKey: "debugMenuEnabled")
        }
    }

    @Published var doubleCopyThresholdMs: Double {
        didSet {
            UserDefaults.standard.set(doubleCopyThresholdMs, forKey: "doubleCopyThresholdMs")
        }
    }

    @Published var llmEnabled: Bool {
        didSet {
            UserDefaults.standard.set(llmEnabled, forKey: "llmEnabled")
        }
    }

    @Published var llmModel: String {
        didSet {
            UserDefaults.standard.set(llmModel, forKey: "llmModel")
        }
    }

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.debugMenuEnabled = UserDefaults.standard.bool(forKey: "debugMenuEnabled")

        let stored = UserDefaults.standard.double(forKey: "doubleCopyThresholdMs")
        self.doubleCopyThresholdMs = stored > 0 ? stored : 280

        self.llmEnabled = UserDefaults.standard.object(forKey: "llmEnabled") as? Bool ?? true
        let storedModel = UserDefaults.standard.string(forKey: "llmModel")
        self.llmModel = storedModel.flatMap(ModelDefinition.find)?.id ?? ModelDefinition.defaultId
        UserDefaults.standard.set(llmModel, forKey: "llmModel")

        syncLaunchAtLoginState()
    }

    private func syncLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            let currentState = SMAppService.mainApp.status == .enabled
            if launchAtLogin != currentState {
                launchAtLogin = currentState
            }
        }
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.error("Failed to update launch at login: \(error)", category: .general)
            }
        }
    }
}
