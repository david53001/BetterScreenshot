import AppKit

/// An image view that drags out a temporary PNG file. The temp file is treated
/// as disposable: it is deleted a few minutes after the drag ends, so dragging
/// the screenshot into a chat/Finder/terminal leaves nothing behind — but stays
/// alive long enough for targets that read the file lazily (a terminal you drop
/// a path into and submit later, a chat you upload-on-send).
public final class DraggableImageView: NSImageView, NSDraggingSource {
    public var fileURLProvider: (() -> URL?)?
    /// Called when a drag finishes. `true` if it was actually dropped somewhere.
    public var onDragEnded: ((Bool) -> Void)?

    private var mouseDownPoint: NSPoint?

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
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        if let img = image { item.setDraggingFrame(bounds, contents: img) }
        beginDraggingSession(with: [item], event: event, source: self)
    }

    public func draggingSession(_ session: NSDraggingSession,
                                endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let droppedSomewhere = operation != []
        // The dragged file is left on disk for a drop target that reads it lazily (a
        // terminal you paste a path into and submit a while later). The app's temp
        // sweep deletes it once it passes the user's retention window.
        onDragEnded?(droppedSomewhere)
    }
}
