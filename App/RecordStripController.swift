import AppKit
import RecordingKit

/// The pre-record control strip: target buttons + per-recording toggles.
/// Lives in App because it bridges RecordingConfig ↔ SettingsStore.
@MainActor
final class RecordStripController {
    private var panel: NSPanel?
    private let store: SettingsStore

    var onFullScreen: (() -> Void)?
    var onArea: (() -> Void)?
    var onCancel: (() -> Void)?

    init(store: SettingsStore) { self.store = store }

    var isVisible: Bool { panel != nil }

    func show(on screen: NSScreen) {
        guard panel == nil else { return }
        let strip = NSStackView()
        strip.orientation = .horizontal
        strip.spacing = 10
        strip.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        let full = NSButton(title: "Record Full Screen", target: self,
                            action: #selector(fullScreen))
        full.bezelStyle = .rounded
        let area = NSButton(title: "Record Area…", target: self, action: #selector(areaSelect))
        area.bezelStyle = .rounded

        let format = NSSegmentedControl(labels: ["MP4", "GIF"], trackingMode: .selectOne,
                                        target: self, action: #selector(formatChanged(_:)))
        format.selectedSegment = store.recording.format == .mp4 ? 0 : 1

        func toggle(_ symbol: String, _ tip: String, _ state: Bool,
                    _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol,
                                            accessibilityDescription: tip)!,
                             target: self, action: action)
            b.setButtonType(.toggle)
            b.bezelStyle = .rounded
            b.state = state ? .on : .off
            b.toolTip = tip
            return b
        }
        let mic = toggle("mic", "Record microphone", store.recording.microphone,
                         #selector(micChanged(_:)))
        let sys = toggle("speaker.wave.2", "Record system audio", store.recording.systemAudio,
                         #selector(sysChanged(_:)))
        let cam = toggle("video", "Show camera bubble", store.recording.camera,
                         #selector(camChanged(_:)))

        let cancel = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                             accessibilityDescription: "Cancel")!,
                              target: self, action: #selector(cancelTapped))
        cancel.isBordered = false

        for v in [full, area, format, mic, sys, cam, cancel] { strip.addArrangedSubview(v) }

        let size = strip.fittingSize
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.minY + 60,
                           width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        strip.frame = CGRect(origin: .zero, size: size)
        p.contentView = strip
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    @objc private func fullScreen() { onFullScreen?() }
    @objc private func areaSelect() { onArea?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func formatChanged(_ sender: NSSegmentedControl) {
        store.recording.format = sender.selectedSegment == 0 ? .mp4 : .gif
        store.persist()
    }
    @objc private func micChanged(_ sender: NSButton) {
        store.recording.microphone = sender.state == .on; store.persist()
    }
    @objc private func sysChanged(_ sender: NSButton) {
        store.recording.systemAudio = sender.state == .on; store.persist()
    }
    @objc private func camChanged(_ sender: NSButton) {
        store.recording.camera = sender.state == .on; store.persist()
    }
}
