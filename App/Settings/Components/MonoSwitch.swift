import SwiftUI

/// Custom `ToggleStyle` for the JVoice monochrome theme: white track + black knob when ON,
/// dark track + light knob when OFF (a native macOS `Toggle` can't invert track+knob colors).
struct MonoSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: SettingsTheme.Metrics.switchTrackRadius)
            .fill(configuration.isOn ? SettingsTheme.accent : SettingsTheme.border)
            .frame(width: SettingsTheme.Metrics.switchWidth, height: SettingsTheme.Metrics.switchHeight)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(configuration.isOn ? Color.black : SettingsTheme.switchOffKnob)
                    .frame(width: SettingsTheme.Metrics.switchKnob, height: SettingsTheme.Metrics.switchKnob)
                    .padding(2)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture {
                configuration.isOn.toggle()
            }
    }
}

extension ToggleStyle where Self == MonoSwitchStyle {
    static var mono: MonoSwitchStyle { .init() }
}
