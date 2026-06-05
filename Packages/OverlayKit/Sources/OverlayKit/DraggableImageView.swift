import AppKit

/// An image view that drags out a temporary PNG file. The temp file is treated
/// as disposable: it is deleted shortly after the drag ends (by which time the
/// drop target has copied it), so dragging the screenshot into a chat/Finder
/// leaves nothing behind.
public final class DraggableImageView: NSImageView, NSDraggingSource {
    public var fileURLProvider: (() -> URL?)?
    /// Called when a drag finishes. `true` if it was actually dropped somewhere.
    public var onDragEnded: ((Bool) -> Void)?
    /// Temp-PNG drags clean up after themselves; set false when the dragged
    /// URL is a real saved file (e.g. a recording) that must survive.
    public var deletesFileAfterDrag = true

    private var mouseDownPoint: NSPoint?
    private var draggedTempDir: URL?

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    public override func mouseDown(with event: NSEvent) {
        // Record the start; only begin a drag once the pointer actually moves,
        // so a plain click on the thumbnail doesn't fire a zero-length drag.
        mouseDownPoint = event.locationInWindow
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - down.x, p.y - down.y) >= 4 else { return }
        mouseDownPoint = nil

        guard let url = fileURLProvider?() else { return }
        draggedTempDir = url.deletingLastPathComponent()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        if let img = image { item.setDraggingFrame(bounds, contents: img) }
        beginDraggingSession(with: [item], event: event, source: self)
    }

    public func draggingSession(_ session: NSDraggingSession,
                                endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let droppedSomewhere = operation != []
        // Clean up the temp file a few seconds later — long enough for the drop
        // target to have read it.
        if deletesFileAfterDrag, let dir = draggedTempDir {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        draggedTempDir = nil
        onDragEnded?(droppedSomewhere)
    }
}
