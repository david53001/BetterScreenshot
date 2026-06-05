import AppKit
import ScreenCaptureKit
import CaptureKit
import OverlayKit
import EditorKit

@MainActor
final class CaptureCoordinator {
    private let service = CaptureService()
    private let settings: SettingsStore
    private let overlay = SelectionOverlayController()
    // Shared with RecordingCoordinator so screenshot and recording overlays
    // stack together at the corner instead of overlapping.
    private let quickAccess: QuickAccessStackController
    private let hud = HUDController()
    private let pins = PinPanelController()

    /// Filled in by Plan 3 to present the annotation editor. Nil = stub.
    var editorPresenter: ((CGImage) -> Void)?

    /// Set by the app delegate; presents the one-button permission setup window.
    var presentSetup: (() -> Void)?

    /// Set by the app delegate; nil until then (history silently skipped).
    var history: HistoryService?

    private var editorController: EditorWindowController?

    func presentEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image)
        controller.onCopy = { [weak self] img in self?.copy(img) }
        controller.onSave = { [weak self] img in self?.save(img) }
        controller.onPin = { [weak self] img in self?.pin(img) }
        editorController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(settings: SettingsStore, quickAccess: QuickAccessStackController) {
        self.settings = settings
        self.quickAccess = quickAccess
    }

    func captureArea() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID),
                                  sourceRect: result.globalRect) }
        }
    }

    func captureFullscreen() {
        guard ensurePermission() else { return }
        Task { await run(.fullscreen(displayID: CGMainDisplayID())) }
    }

    func captureFrontWindow() {
        guard ensurePermission() else { return }
        Task { if let id = await frontmostWindowID() { await run(.window(windowID: id)) } }
    }

    /// Capture Text (OCR + QR): drag a region; the recognized text — or a QR
    /// code's payload, which wins — lands on the clipboard. HUD confirms.
    func captureText() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.runCaptureText(result) }
        }
    }

    private func runCaptureText(_ result: SelectionResult) async {
        do {
            let image = try await service.capture(
                .area(rect: result.globalRect, displayID: result.displayID))
            // Vision's perform() blocks — keep it off the main actor.
            let recognition = try await Task.detached {
                try TextRecognizer.recognize(in: image)
            }.value
            if let payload = recognition.clipboardString {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(payload, forType: .string)
            }
            hud.show(recognition.hudMessage, on: screen(for: result.displayID))
        } catch {
            NSLog("Capture Text failed: \(error)")
            hud.show("Capture Text failed", on: screen(for: result.displayID))
        }
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        } ?? NSScreen.main
    }

    private func run(_ target: CaptureTarget, sourceRect: CGRect? = nil) async {
        do {
            let image = try await service.capture(target)
            handle(image, sourceRect: sourceRect)
        } catch {
            NSLog("Capture failed: \(error)")
            hud.show("Capture failed")
        }
    }

    private func handle(_ image: CGImage, sourceRect: CGRect?) {
        // Silent bookkeeping first, so even copy-only captures are recoverable.
        let historyID = history?.recordScreenshot(image)
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image, sourceRect: sourceRect, historyID: historyID)
        }
    }

    private func presentOverlay(_ image: CGImage, sourceRect: CGRect?, historyID: UUID?) {
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        guard let screen = NSScreen.main else { copy(image); save(image); return }
        let actions = QuickAccessActions(
            onCopy: { [weak self] in self?.copy(image); self?.hud.show("Copied") },
            // The overlay's download button always lands in the macOS screenshot folder.
            onSave: { [weak self] in self?.save(image, to: SettingsStore.systemScreenshotLocation()) },
            onAnnotate: { [weak self] in self?.annotate(image) },
            onPin: { [weak self] in self?.pin(image, near: sourceRect) },
            fileURLForDrag: { TempImageWriter.writePNG(image, fileName: FileNamer.fileName(for: Date(), ext: "png")) })
        let corner = settings.settings.overlayCorner
        // visibleFrame excludes the Dock and menu bar, so the overlay sits above
        // the Dock instead of being tucked into the very bottom corner behind it.
        let frame = screen.visibleFrame
        quickAccess.present(image: nsImage, actions: actions, onDismissed: { [weak self] reason in
            // ✕-close and eviction are "accidental" — deliberate actions aren't restorable.
            if reason == .closed || reason == .evicted {
                self?.history?.noteOverlayClosed(historyID: historyID)
            }
        }) { index in
            OverlayPositioner.stackedOrigin(corner: corner,
                                            overlaySize: CGSize(width: 220, height: 168),
                                            screenFrame: frame, margin: 24, index: index)
        }
    }

    /// Re-presents a Quick Access card for a history entry (Restore Recently Closed).
    func presentOverlayFromHistory(_ image: CGImage, historyID: UUID) {
        presentOverlay(image, sourceRect: nil, historyID: historyID)
    }

    /// Plan 3 replaces the stub body via `editorPresenter`.
    func annotate(_ image: CGImage) {
        if let present = editorPresenter { present(image) }
        else { NSLog("Annotate requested — editor arrives in Plan 3") }
    }

    /// Pins the image as a floating panel — at its original on-screen location
    /// when known, else centered on the main screen.
    func pin(_ image: CGImage, near sourceRect: CGRect? = nil) {
        guard image.width > 0, image.height > 0 else { return }
        let screen = sourceRect.flatMap { r in NSScreen.screens.first { $0.frame.intersects(r) } }
            ?? NSScreen.main
        guard let screen else { return }
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        let style = PinStyle(cornerRadius: CGFloat(settings.settings.pinCornerRadius),
                             shadow: settings.settings.pinShadow)
        let actions = PinActions(
            onCopy: { [weak self] in
                self?.copy(image)
                // Re-resolve at click time: the original display may be gone.
                let liveScreen = NSScreen.screens.first { $0 === screen } ?? NSScreen.main
                self?.hud.show("Copied", on: liveScreen)
            },
            onSave: { [weak self] in self?.save(image) })
        pins.pin(image: nsImage,
                 pixelSize: CGSize(width: image.width, height: image.height),
                 sourceRect: sourceRect, on: screen, style: style, actions: actions)
    }

    func pinFromClipboard() {
        guard let ns = NSPasteboard.general.readObjects(forClasses: [NSImage.self],
                                                        options: nil)?.first as? NSImage,
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            hud.show("No image on clipboard", on: NSScreen.main)
            return
        }
        pin(cg)
    }

    var clipboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(); nsImage.addRepresentation(rep)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func save(_ image: CGImage, to directory: URL? = nil) {
        let dir = directory ?? settings.saveDirectory
        let isPNG = settings.settings.format == .png
        let format: ImageFormat = isPNG ? .png : .jpg(quality: 0.9)
        guard let data = ImageEncoder.encode(image, as: format) else {
            hud.show("Couldn't save — image encoding failed")
            return
        }
        let name = FileNamer.fileName(for: Date(), ext: isPNG ? "png" : "jpg")
        do {
            // The chosen folder may have been deleted/renamed since it was set.
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name))
        } catch {
            NSLog("Save failed: \(error)")
            hud.show("Couldn't save screenshot")
        }
    }

    private func ensurePermission() -> Bool {
        if PermissionManager.hasScreenRecordingPermission { return true }
        presentSetup?()   // one-button setup window owns the whole grant flow
        return false
    }

    private func frontmostWindowID() async -> CGWindowID? {
        let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        return content?.windows.first(where: { $0.isOnScreen && $0.title?.isEmpty == false })?.windowID
    }
}
