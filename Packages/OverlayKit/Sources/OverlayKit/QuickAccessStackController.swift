import AppKit

/// Manages up to `maxCount` post-capture overlays stacked at a screen corner.
/// Index 0 is the newest capture and sits at the corner slot; older overlays
/// step away from the screen edge. A capture beyond the limit evicts the
/// oldest; dismissing any overlay compacts the stack. Slot positions are
/// injected via `originForIndex` so OverlayKit needs no positioning logic.
@MainActor
public final class QuickAccessStackController {
    public let maxCount = 3
    private var entries: [QuickAccessOverlayController] = []   // index 0 = newest
    private var originForIndex: ((Int) -> CGPoint)?

    public init() {}

    public func present(image: NSImage, actions: QuickAccessActions,
                        originForIndex: @escaping (Int) -> CGPoint) {
        self.originForIndex = originForIndex
        if entries.count == maxCount, let oldest = entries.last {
            entries.removeLast()
            oldest.dismiss()   // its onDismissed no-ops: already removed
        }
        let controller = QuickAccessOverlayController()
        controller.onDismissed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.entries.removeAll { $0 === controller }
            self.restack()
        }
        entries.insert(controller, at: 0)
        controller.present(image: image, at: originForIndex(0), actions: actions)
        restack()
    }

    private func restack() {
        // Uses the closure captured by the most recent present(): if the
        // corner setting changed since, existing overlays adopt the new
        // corner on the next compaction. Accepted in the spec.
        guard let originForIndex else { return }
        for (i, c) in entries.enumerated() { c.move(to: originForIndex(i)) }
    }
}
