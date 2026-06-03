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
    private let quickAccess = QuickAccessOverlayController()

    /// Filled in by Plan 3 to present the annotation editor. Nil = stub.
    var editorPresenter: ((CGImage) -> Void)?

    private var editorController: EditorWindowController?

    func presentEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image)
        controller.onCopy = { [weak self] img in self?.copy(img) }
        controller.onSave = { [weak self] img in self?.save(img) }
        editorController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(settings: SettingsStore) { self.settings = settings }

    func captureArea() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID)) }
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

    private func run(_ target: CaptureTarget) async {
        do {
            let image = try await service.capture(target)
            handle(image)
        } catch { NSLog("Capture failed: \(error)") }
    }

    private func handle(_ image: CGImage) {
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image)
        }
    }

    private func presentOverlay(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: .zero)
        guard let screen = NSScreen.main else { copy(image); save(image); return }
        let origin = OverlayPositioner.origin(
            corner: settings.settings.overlayCorner,
            overlaySize: CGSize(width: 220, height: 168),
            screenFrame: screen.frame, margin: 16)
        let actions = QuickAccessActions(
            onCopy: { [weak self] in self?.copy(image) },
            onSave: { [weak self] in self?.save(image) },
            onAnnotate: { [weak self] in self?.annotate(image) },
            fileURLForDrag: { TempImageWriter.writePNG(image, fileName: FileNamer.fileName(for: Date(), ext: "png")) })
        quickAccess.present(image: nsImage, at: origin,
                            autoDismissSeconds: settings.settings.overlayAutoDismissSeconds,
                            actions: actions)
    }

    /// Plan 3 replaces the stub body via `editorPresenter`.
    func annotate(_ image: CGImage) {
        if let present = editorPresenter { present(image) }
        else { NSLog("Annotate requested — editor arrives in Plan 3") }
    }

    private func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(); nsImage.addRepresentation(rep)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func save(_ image: CGImage) {
        let isPNG = settings.settings.format == .png
        let format: ImageFormat = isPNG ? .png : .jpg(quality: 0.9)
        guard let data = ImageEncoder.encode(image, as: format) else { return }
        let name = FileNamer.fileName(for: Date(), ext: isPNG ? "png" : "jpg")
        try? data.write(to: settings.saveDirectory.appendingPathComponent(name))
    }

    private func ensurePermission() -> Bool {
        if PermissionManager.hasScreenRecordingPermission { return true }
        PermissionManager.requestScreenRecordingPermission()
        if !PermissionManager.hasScreenRecordingPermission {
            PermissionManager.presentDeniedAlert(); return false
        }
        return true
    }

    private func frontmostWindowID() async -> CGWindowID? {
        let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        return content?.windows.first(where: { $0.isOnScreen && $0.title?.isEmpty == false })?.windowID
    }
}
