import AppKit
import ScreenCaptureKit
import CaptureKit
import OverlayKit

@MainActor
final class CaptureCoordinator {
    private let service = CaptureService()
    private let settings: SettingsStore
    private let overlay = SelectionOverlayController()

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
        let id = CGMainDisplayID()
        Task { await run(.fullscreen(displayID: id)) }
    }

    func captureFrontWindow() {
        guard ensurePermission() else { return }
        // Minimal v1: capture the frontmost on-screen window.
        Task {
            if let id = await frontmostWindowID() { await run(.window(windowID: id)) }
        }
    }

    private func run(_ target: CaptureTarget) async {
        do {
            let image = try await service.capture(target)
            output(image)
        } catch {
            NSLog("Capture failed: \(error)")
        }
    }

    private func output(_ image: CGImage) {
        let behavior = settings.settings.afterCapture
        let format: ImageFormat = settings.settings.format == .png ? .png : .jpg(quality: 0.9)
        if behavior == .copyOnly || behavior == .copyAndSave {
            let rep = NSBitmapImageRep(cgImage: image)
            let nsImage = NSImage(); nsImage.addRepresentation(rep)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        }
        if behavior == .saveOnly || behavior == .copyAndSave {
            guard let data = ImageEncoder.encode(image, as: format) else { return }
            let ext = settings.settings.format == .png ? "png" : "jpg"
            let name = FileNamer.fileName(for: Date(), ext: ext)
            let url = settings.saveDirectory.appendingPathComponent(name)
            try? data.write(to: url)
        }
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
