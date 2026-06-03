import AppKit

/// An image view that starts a file drag (of a temp file URL) when dragged.
public final class DraggableImageView: NSImageView, NSDraggingSource {
    public var fileURLProvider: (() -> URL?)?

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    public override func mouseDown(with event: NSEvent) {
        guard let url = fileURLProvider?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        if let img = image {
            item.setDraggingFrame(bounds, contents: img)
        }
        beginDraggingSession(with: [item], event: event, source: self)
    }
}
