import SwiftUI

/// Neutral pill button for the JVoice monochrome theme (e.g. secondary actions).
struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(SettingsTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.Metrics.pillRadius)
                    .fill(configuration.isPressed ? SettingsTheme.pillPressed : SettingsTheme.pillFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.Metrics.pillRadius)
                    .stroke(SettingsTheme.pillBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { .init() }
}

/// White/accent-filled pill button for the JVoice monochrome theme (e.g. primary actions).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(Color(rgb: 0x0A0A0A))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? SettingsTheme.accentPressed : SettingsTheme.accent)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accentPill: AccentButtonStyle { .init() }
}
