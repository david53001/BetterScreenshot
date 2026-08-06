import AppKit
import SwiftUI
import HistoryKit

/// One file to drag out of History, with the thumbnail to drag under the cursor.
struct HistoryDragItem {
    let url: URL
    let image: NSImage?

    init(url: URL, image: NSImage?) {
        self.url = url
        self.image = image
    }
}

/// A transparent AppKit layer over a History grid cell. It exists for two things
/// SwiftUI can't do on macOS 14: read the modifier keys held during a click, and
/// start a dragging session carrying more than one file.
struct HistoryItemInteraction: NSViewRepresentable {
    /// (modifier, clickCount) — clickCount 2 is the open/annotate gesture.
    let onClick: (HistoryClickModifier, Int) -> Void
    /// Evaluated at drag time, before a plain click has been applied — so a
    /// drag started on one of several selected cells still sees all of them.
    let dragItems: () -> [HistoryDragItem]

    func makeNSView(context: Context) -> HistoryItemView {
        let view = HistoryItemView()
        view.onClick = onClick
        view.dragItems = dragItems
        return view
    }

    func updateNSView(_ view: HistoryItemView, context: Context) {
        view.onClick = onClick
        view.dragItems = dragItems
    }
}

final class HistoryItemView: NSView, NSDraggingSource {
    var onClick: ((HistoryClickModifier, Int) -> Void)?
    var dragItems: (() -> [HistoryDragItem])?

    private var mouseDownPoint: NSPoint?
    /// A plain click waiting to see whether this turns into a drag.
    private var pendingClick: (modifier: HistoryClickModifier, clicks: Int)?

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        let modifier = Self.modifier(for: event)
        if event.clickCount >= 2 || modifier != .none {
            // Modifier clicks and double-clicks act on press, as in Finder.
            onClick?(modifier, event.clickCount)
            pendingClick = nil
        } else {
            // A plain press on an already-selected cell must not collapse the
            // selection yet — that would strip a multi-file drag down to one
            // file. Hold it until mouseUp, which only fires if no drag began.
            pendingClick = (modifier, event.clickCount)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Only start a drag once the pointer actually moves, so a plain click
        // never fires a zero-length drag. Same 4pt threshold as DraggableImageView.
        guard let down = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - down.x, p.y - down.y) >= 4 else { return }
        mouseDownPoint = nil
        pendingClick = nil          // a drag is not a click

        let items = dragItems?() ?? []
        guard !items.isEmpty else { return }

        let dragging: [NSDraggingItem] = items.enumerated().map { index, item in
            let di = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            // Fan the thumbnails out slightly so a multi-file drag reads as a stack.
            let offset = CGFloat(index) * 8
            if let image = item.image {
                di.setDraggingFrame(bounds.offsetBy(dx: offset, dy: -offset), contents: image)
            }
            return di
        }
        beginDraggingSession(with: dragging, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        guard let pending = pendingClick else { return }
        pendingClick = nil
        onClick?(pending.modifier, pending.clicks)
    }

    private static func modifier(for event: NSEvent) -> HistoryClickModifier {
        // Shift wins over Command when both are held, matching Finder.
        if event.modifierFlags.contains(.shift) { return .shift }
        if event.modifierFlags.contains(.command) { return .command }
        return .none
    }
}
