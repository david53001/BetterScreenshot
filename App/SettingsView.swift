import SwiftUI
import CaptureKit

/// Closures the Shortcuts tab needs from the app layer (AppDelegate owns the
/// rebind transaction because it touches HotKeyManager + menu + persistence).
struct ShortcutActions {
    /// Bind combo (nil = clear) to action. Returns an error message, or nil on success.
    var update: (HotkeyCombo?, HotkeyAction) -> String?
    var restoreDefaults: () -> Void
    /// true while a recorder well is active → suspend all hotkeys.
    var recordingChanged: (Bool) -> Void
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let shortcuts: ShortcutActions

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(store: store, actions: shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480)
        .padding(20)
    }
}

private struct GeneralTab: View {
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

private struct ShortcutsTab: View {
    @ObservedObject var store: SettingsStore
    let actions: ShortcutActions
    @State private var status = ""
    @State private var recordingAction: HotkeyAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title)
                    if store.failedActions.contains(action) {
                        Text("couldn't register")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    ShortcutRecorderField(
                        combo: store.bindings.combo(for: action),
                        isRecording: Binding(
                            get: { recordingAction == action },
                            set: { setRecording($0 ? action : nil) }),
                        onCombo: { combo in
                            status = actions.update(combo, action) ?? ""
                        })
                        .frame(width: 130, height: 22)
                    Button {
                        status = actions.update(nil, action) ?? ""
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(store.bindings.combo(for: action) == nil)
                        .help("Remove shortcut")
                }
            }
            Divider().padding(.vertical, 4)
            Text("⇧⌘5 is reserved for Start/Stop Recording (coming soon).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Restore Defaults") {
                    actions.restoreDefaults()
                    status = ""
                }
                Spacer()
                Text(status).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { setRecording(nil) }
    }

    /// Tracks which row is recording; suspends/resumes hotkeys on transitions.
    private func setRecording(_ action: HotkeyAction?) {
        let wasRecording = recordingAction != nil
        recordingAction = action
        let isRecording = action != nil
        if wasRecording != isRecording { actions.recordingChanged(isRecording) }
    }
}
