import AppKit
import ScreenCaptureKit
import CaptureKit
import OverlayKit
import RecordingKit

/// Orchestrates the recording lifecycle: strip → engine + panels → save/convert.
@MainActor
final class RecordingCoordinator {
    private let settings: SettingsStore
    private let recorder = ScreenRecorder()
    private let strip: RecordStripController
    private let selection = SelectionOverlayController()
    private let bubble = CameraBubbleController()
    private let clicks = ClickHighlighter()
    private let keystrokes = KeystrokeOverlayController()
    private let hud = HUDController()
    private var state = RecorderState.idle
    private var timer: Timer?
    private var isTerminating = false
    private var tempOutputURL: URL?

    /// Set by the app delegate; presents the one-button permission setup window.
    var presentSetup: (() -> Void)?
    /// Menu-bar state: (recording?, elapsed string). Called on every change/tick.
    var onStateChange: ((Bool, String?) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        self.strip = RecordStripController(store: settings)
        strip.onFullScreen = { [weak self] in self?.beginFullScreen() }
        strip.onArea = { [weak self] in self?.beginAreaSelection() }
        strip.onCancel = { [weak self] in self?.cancelStrip() }
        recorder.onStreamError = { [weak self] _ in
            Task { @MainActor in self?.streamFailed() }
        }
    }

    var isRecording: Bool { if case .recording = state { return true }; return false }

    /// The smart ⌘⇧5 entry point: idle → strip · armed → cancel · recording → stop.
    func toggle() {
        switch state {
        case .idle: arm()
        case .armed: cancelStrip()
        case .recording: Task { await stop() }
        case .finishing: break   // busy — ignore
        }
    }

    private func arm() {
        guard PermissionManager.hasScreenRecordingPermission else {
            presentSetup?()
            return
        }
        guard state.transition(.arm) else { return }
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        if let screen { strip.show(on: screen) }
    }

    private func cancelStrip() {
        // ⌘⇧5 while the area-selection overlay is up: tear it down too.
        selection.cancel()
        strip.hide()
        state.transition(.reset)
    }

    private func beginFullScreen() {
        guard let screen = stripScreen() else { return }
        strip.hide()
        Task { await begin(globalRect: nil, screen: screen) }
    }

    private func beginAreaSelection() {
        strip.hide()
        selection.present { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard let result,
                      let screen = NSScreen.screens.first(where: {
                          $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                              as? CGDirectDisplayID == result.displayID
                      }) else {
                    self.state.transition(.reset)
                    return
                }
                await self.begin(globalRect: result.globalRect, screen: screen)
            }
        }
    }

    private func stripScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    /// Start the engine for `globalRect` (nil = full screen) on `screen`.
    private func begin(globalRect: CGRect?, screen: NSScreen) async {
        // A ⌘⇧5 cancel can land while the selection overlay or permission prompts
        // were up — only proceed if we're still armed.
        guard case .armed = state else { return }
        let config = settings.recording
        guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            state.transition(.reset)
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw RecorderError.writerFailed }

            let scale = screen.backingScaleFactor
            // sourceRect: display-relative, top-left origin, points.
            var sourceRect: CGRect?
            var pixelSize = CGSize(width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
            if let globalRect {
                let local = CaptureGeometry.pixelRect(forGlobalRect: globalRect,
                                                      inDisplayFrame: screen.frame,
                                                      scale: 1)   // points, top-left
                sourceRect = local
                pixelSize = CGSize(width: local.width * scale, height: local.height * scale)
            }

            // Even pixel dimensions keep H.264 encoders happy.
            pixelSize.width = (pixelSize.width / 2).rounded(.down) * 2
            pixelSize.height = (pixelSize.height / 2).rounded(.down) * 2

            if config.microphone {
                _ = await MicCapturer.ensurePermission()
            }
            if config.camera, await CameraBubbleController.ensurePermission() {
                bubble.show(near: globalRect ?? screen.frame, on: screen,
                            diameter: config.cameraSize.diameter)
            }
            if config.clickHighlights { clicks.start(on: screen) }
            if config.keystrokeOverlay { keystrokes.start(on: screen) }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let ext = "mp4"   // GIF converts after the fact
            let name = FileNamer.fileName(for: Date(), ext: ext, prefix: "Recording")
            let url = config.format == .gif
                ? FileManager.default.temporaryDirectory.appendingPathComponent(name)
                : settings.saveDirectory.appendingPathComponent(name)
            tempOutputURL = config.format == .gif ? url : nil

            try await recorder.start(filter: filter, pixelSize: pixelSize,
                                     sourceRect: sourceRect, config: config, outputURL: url)
            guard state.transition(.begin(Date())) else {
                // Cancelled (⌘⇧5) during engine startup: stop and discard.
                _ = try? await recorder.stop()
                try? FileManager.default.removeItem(at: url)
                tearDownPanels()
                notify()
                return
            }
            startTimer()
            notify()
        } catch {
            tearDownPanels()
            state.transition(.reset)
            hud.show("Couldn't start recording", on: screen)
            notify()
        }
    }

    private func stop() async {
        guard state.transition(.finish) else { return }
        stopTimer()
        notify()
        let config = settings.recording
        do {
            let mp4 = try await recorder.stop()
            tearDownPanels()
            if config.format == .gif, !isTerminating {
                hud.show("Converting to GIF…")
                let gifName = FileNamer.fileName(for: Date(), ext: "gif", prefix: "Recording")
                let gifURL = settings.saveDirectory.appendingPathComponent(gifName)
                do {
                    try await GIFExporter.export(mp4: mp4, to: gifURL)
                    try? FileManager.default.removeItem(at: mp4)
                    hud.show("GIF saved")
                } catch {
                    // Keep the MP4 so the recording isn't lost.
                    let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                    let dest = settings.saveDirectory.appendingPathComponent(mp4Name)
                    try? FileManager.default.moveItem(at: mp4, to: dest)
                    hud.show("Saved as MP4 (GIF conversion failed)")
                }
            } else if config.format == .gif {
                // Quitting: no time for conversion — keep the MP4 so nothing is lost.
                let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                try? FileManager.default.moveItem(
                    at: mp4, to: settings.saveDirectory.appendingPathComponent(mp4Name))
            } else {
                hud.show("Recording saved")
            }
        } catch {
            if let tempOutputURL { try? FileManager.default.removeItem(at: tempOutputURL) }
            tearDownPanels()
            hud.show("Recording failed")
        }
        state.transition(.reset)
        tempOutputURL = nil
        notify()
    }

    /// Best-effort stop for app termination. Spins the main run loop (instead of
    /// blocking on a semaphore, which would deadlock the MainActor task) so the
    /// async finalize can complete before the process exits.
    func stopForTermination() {
        guard isRecording else { return }
        isTerminating = true
        var done = false
        Task { @MainActor in
            await self.stop()
            done = true
        }
        let deadline = Date().addingTimeInterval(3)
        while !done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func streamFailed() {
        guard isRecording else { return }
        Task { await stop() }
    }

    private func tearDownPanels() {
        bubble.hide()
        clicks.stop()
        keystrokes.stop()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.notify() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func notify() {
        onStateChange?(isRecording, state.elapsedString(now: Date()))
    }
}
