import SwiftUI

// Constants for the "JVoice" monochrome Settings theme (parity with the Windows port's
// settings redesign). See docs/WINDOWS-TO-MAC-PARITY.md §1.3–1.6 for the source values.
// No UI wiring yet — this file only defines the palette/typography/metrics constants that
// later custom controls will read.

extension Color {
    /// 24-bit 0xRRGGBB with separate alpha.
    init(rgb: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF)/255,
                  green: Double((rgb >> 8) & 0xFF)/255,
                  blue: Double(rgb & 0xFF)/255,
                  opacity: alpha)
    }
    /// 32-bit 0xAARRGGBB.
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF)/255,
                  green: Double((argb >> 8) & 0xFF)/255,
                  blue: Double(argb & 0xFF)/255,
                  opacity: Double((argb >> 24) & 0xFF)/255)
    }
}

enum SettingsTheme {
    // MARK: - Palette (§1.3)

    // Solids
    static let windowBG = Color(rgb: 0x000000)
    static let chrome = Color(rgb: 0x0A0A0A)
    static let card = Color(rgb: 0x0E0E0E)
    static let controlRest = Color(rgb: 0x1A1A1A)
    static let controlHover = Color(rgb: 0x242424)
    static let controlPressed = Color(rgb: 0x2E2E2E)
    static let border = Color(rgb: 0x2A2A2A)
    static let textPrimary = Color(rgb: 0xF5F5F7)
    static let label = Color(rgb: 0xD9D9D9)
    static let headerLabel = Color(rgb: 0x8E8E93)
    static let subLabel = Color(rgb: 0x6E6E73)
    static let faint = Color(rgb: 0x595959)
    static let accent = Color(rgb: 0xFFFFFF)
    static let accentHover = Color(rgb: 0xE6E6E6)
    static let accentPressed = Color(rgb: 0xCFCFCF)
    static let switchOffKnob = Color(rgb: 0xCFCFCF)

    // Alpha-literals
    static let segmentHover = Color(argb: 0x12FFFFFF)
    static let segmentChecked = Color(argb: 0x29FFFFFF)
    static let comboHighlight = Color(argb: 0x29FFFFFF)
    static let pillFill = Color(argb: 0x1FFFFFFF)
    static let pillHover = Color(argb: 0x2BFFFFFF)
    static let pillPressed = Color(argb: 0x3AFFFFFF)
    static let pillBorder = Color(argb: 0x3DFFFFFF)
    static let infoIdle = Color(argb: 0x1FFFFFFF)
    static let infoHover = Color(argb: 0x40FFFFFF)
    static let infoRing = Color(argb: 0x40FFFFFF)
    static let infoGlyph = Color(argb: 0xE6FFFFFF)
    static let sliderTrack = Color(argb: 0x1AFFFFFF)
    static let cardTopHairline = Color(argb: 0x26FFFFFF)
    static let scrollThumb = Color(argb: 0x33FFFFFF)

    // MARK: - Metrics (§1.5 / §1.6)

    enum Metrics {
        static let windowWidth: CGFloat = 960
        static let outerMargin: CGFloat = 18
        static let columnWidth: CGFloat = 297
        static let gutter: CGFloat = 16
        static let cardGap: CGFloat = 12
        static let cardRadius: CGFloat = 10
        static let cardBorder: CGFloat = 1
        static let switchWidth: CGFloat = 38
        static let switchHeight: CGFloat = 22
        static let switchTrackRadius: CGFloat = 11
        static let switchKnob: CGFloat = 18
        static let segmentRadius: CGFloat = 6
        static let pillRadius: CGFloat = 7
        static let infoDiameter: CGFloat = 16
        static let sliderTrackHeight: CGFloat = 4
        static let sliderThumb: CGFloat = 16
    }

    // MARK: - Typography (§1.4)

    enum Font {
        static let headerTitle = SwiftUI.Font.system(size: 18, weight: .bold)
        /// Uppercase the string at the call site.
        static let cardHeader = SwiftUI.Font.system(size: 10, weight: .bold)
        static let fieldLabel = SwiftUI.Font.system(size: 11.5, weight: .semibold)
        static let rowTitle = SwiftUI.Font.system(size: 12.5, weight: .medium)
        static let rowSubLabel = SwiftUI.Font.system(size: 10.5, weight: .regular)
        static let subtitle = SwiftUI.Font.system(size: 11.5, weight: .regular)
        static let footer = SwiftUI.Font.system(size: 11, weight: .regular)
        static let segment = SwiftUI.Font.system(size: 12, weight: .regular)
        static let sliderValue = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let pill = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let tooltipTitle = SwiftUI.Font.system(size: 12.5, weight: .semibold)
        static let tooltipBody = SwiftUI.Font.system(size: 11.5, weight: .regular)
        /// Apply `.italic()` at the call site.
        static let tooltipExample = SwiftUI.Font.system(size: 11, weight: .regular)
    }
}
