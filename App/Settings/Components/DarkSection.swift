import SwiftUI

/// Card container for the JVoice monochrome Settings theme: a glowing-dot + uppercase title
/// header, a hairline divider, then arbitrary content.
struct DarkSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .shadow(color: .white.opacity(0.6), radius: 7)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SettingsTheme.headerLabel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(SettingsTheme.border)
                .frame(height: 1)

            content
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: SettingsTheme.Metrics.cardRadius)
                .fill(SettingsTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.Metrics.cardRadius)
                .stroke(SettingsTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.Metrics.cardRadius))
    }
}
