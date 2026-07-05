import AppKit
import SwiftUI
import CoreText

/// CopyCopy design-system tokens — the "Foundry" system.
///
/// Foundry is an industrial palette: warm concrete surfaces, iron ink, machined
/// (not pill-soft) radii, and a single accent that is the one bright signal in
/// the room. CopyCopy overrides Foundry's default rust accent with **steel-blue**.
///
/// Interface voice is DM Sans; the "machine voice" (IDs, counts, key badges,
/// eyebrows, timestamps) is IBM Plex Mono — both bundled and registered at
/// launch (see `BrandFonts`).
///
/// Every color is a dynamic `NSColor` so it tracks the system light/dark
/// appearance exactly the way Foundry mirrors its tokens under the `.dark`
/// (graphite) scope.
extension Color {
    // MARK: Accent — steel-blue (CopyCopy's scene override of Foundry rust)

    /// Primary action / selection fill. Light `#2f6d9e` · dark lifts for contrast.
    static let ccAccent = dynamicBrand(light: 0x2F6D9E, dark: 0x4C93C8)
    /// Hover state for the accent. Light `#255d88` · dark.
    static let ccAccentHover = dynamicBrand(light: 0x255D88, dark: 0x5DA1D2)
    /// Soft accent tint fill for chips/pills. Light `#e4eef7` · dark graphite-steel.
    static let ccAccentSoft = dynamicBrand(light: 0xE4EEF7, dark: 0x1C2E3D)
    /// Text/icon color on an accent-subtle fill (entity chip). Light `#1e5a8a` · dark.
    static let ccAccentText = dynamicBrand(light: 0x1E5A8A, dark: 0x9CC7E6)

    // MARK: Surfaces — warm concrete

    /// Raised elements / cards. Light `#ffffff` · dark darkest ground `#161410`.
    static let ccSurface0 = dynamicBrand(light: 0xFFFFFF, dark: 0x161410)
    /// Page ground / card shade. Light `#f6f4f1` · dark `#1f1c17`.
    static let ccSurface1 = dynamicBrand(light: 0xF6F4F1, dark: 0x1F1C17)
    /// Insets, tracks, hover fills, result well. Light `#ece8e2` · dark `#2a2620`.
    static let ccSurface2 = dynamicBrand(light: 0xECE8E2, dark: 0x2A2620)
    /// Dividers / pressed. Light `#ddd8d0` · dark `#383229`.
    static let ccSurface3 = dynamicBrand(light: 0xDDD8D0, dark: 0x383229)
    /// Sunken paper surface for inset wells — alias of surface-2.
    static let ccSurfaceSunken = ccSurface2

    // MARK: Ink — iron

    /// Headings / primary copy. Light `#1b1916` · dark `#f1ede6`.
    static let ccTextPrimary = dynamicBrand(light: 0x1B1916, dark: 0xF1EDE6)
    /// Body copy. Light `#57534b` · dark `#b3aa9d`.
    static let ccTextSecondary = dynamicBrand(light: 0x57534B, dark: 0xB3AA9D)
    /// Metadata / captions / labels. Light `#918b80` · dark `#7a7367`.
    static let ccTextMuted = dynamicBrand(light: 0x918B80, dark: 0x7A7367)

    // MARK: Borders — hairlines

    /// Default 1px hairline. Light `#e7e2da` · dark `#322d25`.
    static let ccBorder = dynamicBrand(light: 0xE7E2DA, dark: 0x322D25)
    /// Emphasized edges / inputs / key badges. Light `#d8d2c8` · dark `#433d33`.
    static let ccBorderStrong = dynamicBrand(light: 0xD8D2C8, dark: 0x433D33)

    // MARK: Status signals — muted, industrial

    /// Running / done / success. Light `#2f7d53` · dark lifted.
    static let ccSuccess = dynamicBrand(light: 0x2F7D53, dark: 0x57C98A)
    /// Alias for the "agent alive / done" running signal.
    static let ccStatusRunning = ccSuccess
    /// Error / danger. Light `#b53434` · dark `#e0706a`.
    static let ccDanger = dynamicBrand(light: 0xB53434, dark: 0xE0706A)

    private static func dynamicBrand(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }
}

/// Corner radii — machined, not pill-soft — from Foundry `tokens/effects.css`.
enum CCRadius {
    /// Chips, tiny inputs.
    static let xs: CGFloat = 4
    /// Key hints, badges, small chips (panel uses 5 for pills).
    static let badge: CGFloat = 5
    /// Content-type icon tile.
    static let iconTile: CGFloat = 7
    /// Inputs, code/result wells, action rows.
    static let sm: CGFloat = 8
    /// Buttons, feature cards (`--radius-lg`).
    static let md: CGFloat = 12
    /// Scenario cards.
    static let lg: CGFloat = 16
    /// The native floating panel (`--radius-xl`).
    static let panel: CGFloat = 14
}

// MARK: - Fonts

/// Registers the bundled Foundry typefaces (DM Sans + IBM Plex Mono) with the
/// process font manager so `Font.custom` can resolve them. Idempotent.
enum BrandFonts {
    private static var didRegister = false
    private static let fileNames = [
        "DMSans",
        "IBMPlexMono-Regular",
        "IBMPlexMono-Medium",
        "IBMPlexMono-SemiBold",
    ]

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        for name in fileNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// DM Sans — the interface voice. Falls back to the system font if the
    /// bundled face is unavailable.
    static func ccSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BrandFonts.registerIfNeeded()
        return Font.custom("DM Sans", size: size).weight(weight)
    }

    /// IBM Plex Mono — the machine voice (IDs, counts, key badges, eyebrows).
    /// Falls back to the system monospaced font if unavailable.
    static func ccMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BrandFonts.registerIfNeeded()
        return Font.custom("IBM Plex Mono", size: size).weight(weight)
    }
}

private extension NSColor {
    convenience init(rgbHex hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
