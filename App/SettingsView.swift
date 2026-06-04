import SwiftUI
import CaptureKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    guard newValue != LaunchAtLogin.isEnabled else { return }
                    LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled  // revert if it failed
                }
            Picker("After capture", selection: bind(\.afterCapture)) {
                Text("Show overlay").tag(AfterCaptureBehavior.showOverlay)
                Text("Copy to clipboard").tag(AfterCaptureBehavior.copyOnly)
                Text("Save to folder").tag(AfterCaptureBehavior.saveOnly)
                Text("Copy and save").tag(AfterCaptureBehavior.copyAndSave)
            }
            Picker("Format", selection: bind(\.format)) {
                Text("PNG").tag(SettingsImageFormat.png)
                Text("JPG").tag(SettingsImageFormat.jpg)
            }
            Picker("Overlay corner", selection: bind(\.overlayCorner)) {
                Text("Bottom-right").tag(OverlayCorner.bottomRight)
                Text("Bottom-left").tag(OverlayCorner.bottomLeft)
                Text("Top-right").tag(OverlayCorner.topRight)
                Text("Top-left").tag(OverlayCorner.topLeft)
            }
            Toggle("Pin shadow", isOn: bind(\.pinShadow))
            HStack {
                Text("Pin corner radius")
                Slider(value: Binding(
                    get: { Double(store.settings.pinCornerRadius) },
                    set: { store.settings.pinCornerRadius = Int($0); store.persist() }),
                    in: 0...20, step: 1)
                Text("\(store.settings.pinCornerRadius) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Save to: \(store.saveDirectory.path)")
                    .truncationMode(.middle).lineLimit(1)
                Spacer()
                Button("Change…") { chooseFolder() }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func bind<V>(_ keyPath: WritableKeyPath<CaptureSettings, V>) -> Binding<V> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0; store.persist() })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.saveDirectory = url; store.persist()
        }
    }
}
