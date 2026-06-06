import AppKit
import SwiftUI

/// CopyCopy design-system tokens, mirroring `copycopy-design-system/tokens`.
///
/// Warm paper neutrals with a single burnt-orange accent. Every color is a
/// dynamic `NSColor` so it tracks the system light/dark appearance exactly the
/// way the marketing site mirrors its tokens under `prefers-color-scheme: dark`.
/// The indigo→violet brand gradient lives in the app icon only and is not
/// reproduced here.
extension Color {
    /// Burnt orange — links, suggested-action fill, selection. `#d35400` / dark `#e8792b`.
    static let ccAccent = dynamicBrand(light: 0xD35400, dark: 0xE8792B)
    /// Hover state for the accent. `#b8490a` / dark `#f08a42`.
    static let ccAccentHover = dynamicBrand(light: 0xB8490A, dark: 0xF08A42)
    /// Soft accent tint for pills and chips. `#fdf0e6` / dark `#2a1a0a`.
    static let ccAccentSoft = dynamicBrand(light: 0xFDF0E6, dark: 0x2A1A0A)
    /// Success green. `#1f8a4c` / dark `#4ade80`.
    static let ccSuccess = dynamicBrand(light: 0x1F8A4C, dark: 0x4ADE80)
    /// Danger red. `#c0392b` / dark `#ef6b5e`.
    static let ccDanger = dynamicBrand(light: 0xC0392B, dark: 0xEF6B5E)
    /// Sunken paper surface for inset wells. `#f0efec` / dark `#0e0e0d`.
    static let ccSurfaceSunken = dynamicBrand(light: 0xF0EFEC, dark: 0x0E0E0D)
    /// Hairline border. `#e5e4e0` / dark `#2a2a27`.
    static let ccBorder = dynamicBrand(light: 0xE5E4E0, dark: 0x2A2A27)
    /// Strong border. `#d0cfcb` / dark `#3a3a36`.
    static let ccBorderStrong = dynamicBrand(light: 0xD0CFCB, dark: 0x3A3A36)

    private static func dynamicBrand(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }
}

/// Corner radii from `tokens/spacing.css`.
enum CCRadius {
    /// Keyboard keys, tiny chips.
    static let xs: CGFloat = 4
    /// Inputs, code wells, action rows.
    static let sm: CGFloat = 8
    /// Buttons, feature cards.
    static let md: CGFloat = 12
    /// Scenario cards.
    static let lg: CGFloat = 16
    /// The native floating panel.
    static let panel: CGFloat = 14
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
