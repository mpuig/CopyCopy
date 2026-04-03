import Foundation

enum TerminalAppIdentifiers {
    static let exactBundleIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp",
        "dev.warp.warp-stable",
        "com.github.wez.wezterm",
        "org.alacritty",
        "co.zeit.hyper",
        "net.kovidgoyal.kitty",
    ]

    static let bundleIdentifierPrefixes: [String] = [
        "com.googlecode.iterm2",
    ]

    static let nameHints: [String] = [
        "terminal",
        "iterm",
        "ghostty",
        "warp",
        "wezterm",
        "alacritty",
        "hyper",
        "kitty",
    ]

    static func isTerminal(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier {
            let lower = bundleIdentifier.lowercased()
            if Self.exactBundleIdentifiers.contains(lower) {
                return true
            }
            if Self.bundleIdentifierPrefixes.contains(where: { lower.hasPrefix($0) }) {
                return true
            }
        }

        let name = (appName ?? "").lowercased()
        return Self.nameHints.contains { name.contains($0) }
    }
}

enum IDEAppIdentifiers {
    static let exactBundleIdentifiers: Set<String> = [
        "com.apple.dt.xcode",
        "com.microsoft.vscode",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.webstorm",
        "com.jetbrains.goland",
        "com.jetbrains.rubymine",
        "com.jetbrains.clion",
        "com.jetbrains.rider",
        "com.jetbrains.datagrip",
        "com.jetbrains.fleet",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.panic.nova",
        "com.barebones.bbedit",
        "abnerworks.typora",
        "com.cursor.cursor",
        "dev.zed.Zed",
    ]

    static let bundleIdentifierPrefixes: [String] = [
        "com.jetbrains.",
    ]

    static let nameHints: [String] = [
        "xcode",
        "vscode",
        "visual studio code",
        "intellij",
        "pycharm",
        "webstorm",
        "goland",
        "rubymine",
        "clion",
        "rider",
        "sublime",
        "nova",
        "bbedit",
        "cursor",
        "zed",
    ]

    static func isIDE(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier {
            let lower = bundleIdentifier.lowercased()
            if Self.exactBundleIdentifiers.contains(lower) {
                return true
            }
            if Self.bundleIdentifierPrefixes.contains(where: { lower.hasPrefix($0) }) {
                return true
            }
        }

        let name = (appName ?? "").lowercased()
        return Self.nameHints.contains { name.contains($0) }
    }
}

enum EmailAppIdentifiers {
    static let exactBundleIdentifiers: Set<String> = [
        "com.apple.mail",
        "com.microsoft.outlook",
        "com.readdle.smartemail",
        "it.bloop.airmail2",
        "com.freron.mailmate",
        "com.superhuman.mail",
    ]

    static let nameHints: [String] = [
        "mail",
        "outlook",
        "spark",
        "airmail",
        "mailmate",
        "superhuman",
    ]

    static func isEmail(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier {
            let lower = bundleIdentifier.lowercased()
            if Self.exactBundleIdentifiers.contains(lower) {
                return true
            }
        }

        let name = (appName ?? "").lowercased()
        return Self.nameHints.contains { name.contains($0) }
    }
}

enum ChatAppIdentifiers {
    static let exactBundleIdentifiers: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2",
        "com.hnc.discord",
        "ru.keepcoder.telegram",
        "net.whatsapp.whatsapp",
        "com.apple.mobilesms",
        "com.facebook.archon",
        "us.zoom.xos",
        "com.linear",
    ]

    static let nameHints: [String] = [
        "slack",
        "teams",
        "discord",
        "telegram",
        "whatsapp",
        "messages",
        "messenger",
        "zoom",
        "linear",
    ]

    static func isChat(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier {
            let lower = bundleIdentifier.lowercased()
            if Self.exactBundleIdentifiers.contains(lower) {
                return true
            }
        }

        let name = (appName ?? "").lowercased()
        return Self.nameHints.contains { name.contains($0) }
    }
}

enum NotesAppIdentifiers {
    static let exactBundleIdentifiers: Set<String> = [
        "com.apple.notes",
        "notion.id",
        "md.obsidian",
        "net.shinyfrog.bear",
        "com.lukilabs.lukiapp",
    ]

    static let nameHints: [String] = [
        "notes",
        "notion",
        "obsidian",
        "bear",
        "craft",
    ]

    static func isNotes(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier {
            let lower = bundleIdentifier.lowercased()
            if Self.exactBundleIdentifiers.contains(lower) {
                return true
            }
        }

        let name = (appName ?? "").lowercased()
        return Self.nameHints.contains { name.contains($0) }
    }
}

enum BrowserAppIdentifiers {
    static let exactBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "com.operasoftware.opera",
        "com.vivaldi.vivaldi",
        "company.thebrowser.browser",
    ]

    static func isBrowser(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier {
            let lower = bundleIdentifier.lowercased()
            if Self.exactBundleIdentifiers.contains(lower) {
                return true
            }
        }

        let name = (appName ?? "").lowercased()
        return ["safari", "chrome", "firefox", "edge", "brave", "opera", "vivaldi", "arc"].contains { name.contains($0) }
    }
}
