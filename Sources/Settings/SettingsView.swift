import SwiftUI

enum SettingsTab: String, Hashable {
    case general
    case actions
    case about
    case debug
}

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @ObservedObject var actionsStore: CustomActionsStore
    let updater: UpdaterProviding
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsGeneralPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            SettingsActionsPane(actionsStore: actionsStore)
                .tabItem { Label("Actions", systemImage: "sparkles.rectangle.stack") }
                .tag(SettingsTab.actions)

            SettingsAboutPane(updater: updater)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)

            if settings.debugMenuEnabled {
                SettingsDebugPane(settings: settings, model: model)
                    .tabItem { Label("Debug", systemImage: "ladybug") }
                    .tag(SettingsTab.debug)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 450, idealHeight: 550)
        .onChange(of: settings.debugMenuEnabled) { _, newValue in
            if !newValue && selectedTab == .debug {
                selectedTab = .general
            }
        }
    }
}
