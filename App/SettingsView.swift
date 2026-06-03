import SwiftUI
import CaptureKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
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
            Stepper("Auto-dismiss after \(store.settings.overlayAutoDismissSeconds)s",
                    value: Binding(
                        get: { store.settings.overlayAutoDismissSeconds },
                        set: { store.settings.overlayAutoDismissSeconds = $0; store.persist() }),
                    in: 0...30)
            HStack {
                Text("Save to: \(store.saveDirectory.path)")
                    .truncationMode(.middle).lineLimit(1)
                Spacer()
                Button("Change…") { chooseFolder() }
            }
        }
        .padding(20)
        .frame(width: 440)
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
