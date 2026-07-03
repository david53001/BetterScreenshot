import SwiftUI

/// A row of mutually-exclusive segments (short text or glyphs) for the JVoice monochrome theme.
/// Only the leftmost/rightmost segments round their outer corners; a single-segment control
/// rounds all four.
struct SegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let segments: [(value: T, label: String)]

    @State private var hovered: T?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                segmentView(segment: segment, index: index)
            }
        }
    }

    @ViewBuilder
    private func segmentView(segment: (value: T, label: String), index: Int) -> some View {
        let isSelected = segment.value == selection
        let isHovered = hovered == segment.value
        let fill: Color = isSelected
            ? SettingsTheme.segmentChecked
            : (isHovered ? SettingsTheme.segmentHover : SettingsTheme.chrome)
        let textColor: Color = isSelected ? SettingsTheme.accent : SettingsTheme.label
        let shape = cornerShape(for: index)

        Text(segment.label)
            .font(.system(size: 12))
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(shape)
            .overlay(shape.stroke(SettingsTheme.border, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering in
                hovered = hovering ? segment.value : nil
            }
            .onTapGesture {
                selection = segment.value
            }
    }

    private func cornerShape(for index: Int) -> UnevenRoundedRectangle {
        let radius = SettingsTheme.Metrics.segmentRadius
        if segments.count == 1 {
            return UnevenRoundedRectangle(
                topLeadingRadius: radius, bottomLeadingRadius: radius,
                bottomTrailingRadius: radius, topTrailingRadius: radius
            )
        }
        if index == 0 {
            return UnevenRoundedRectangle(
                topLeadingRadius: radius, bottomLeadingRadius: radius,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            )
        }
        if index == segments.count - 1 {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: radius, topTrailingRadius: radius
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 0
        )
    }
}
