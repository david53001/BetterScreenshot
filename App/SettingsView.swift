import SwiftUI
import CaptureKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("After capture", selection: Binding(
                get: { store.settings.afterCapture },
                set: { store.settings.afterCapture = $0; store.persist() })) {
                Text("Copy to clipboard").tag(AfterCaptureBehavior.copyOnly)
                Text("Save to folder").tag(AfterCaptureBehavior.saveOnly)
                Text("Copy and save").tag(AfterCaptureBehavior.copyAndSave)
            }
            Picker("Format", selection: Binding(
                get: { store.settings.format },
                set: { store.settings.format = $0; store.persist() })) {
                Text("PNG").tag(SettingsImageFormat.png)
                Text("JPG").tag(SettingsImageFormat.jpg)
            }
            HStack {
                Text("Save to: \(store.saveDirectory.path)")
                    .truncationMode(.middle).lineLimit(1)
                Spacer()
                Button("Change…") { chooseFolder() }
            }
        }
        .padding(20)
        .frame(width: 420)
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
