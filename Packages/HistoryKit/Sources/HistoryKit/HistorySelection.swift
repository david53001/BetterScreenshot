import Foundation

/// Which modifier the user was holding when they clicked a history item.
public enum HistoryClickModifier {
    case none, command, shift
}

/// The History window's selection: the chosen entries plus the anchor a
/// ⇧-click ranges from.
public struct HistorySelectionState: Equatable {
    public var selected: Set<UUID>
    public var anchor: UUID?

    public init(selected: Set<UUID> = [], anchor: UUID? = nil) {
        self.selected = selected
        self.anchor = anchor
    }
}

/// Standard macOS list-selection arithmetic, kept pure so the History window
/// itself has nothing to branch on. `order` is the displayed order — for the
/// History window that is `HistoryIndex.entries` (newest first).
public enum HistorySelection {

    public static func click(on id: UUID,
                             modifier: HistoryClickModifier,
                             order: [UUID],
                             state: HistorySelectionState) -> HistorySelectionState {
        guard let clicked = order.firstIndex(of: id) else { return state }

        switch modifier {
        case .none:
            return HistorySelectionState(selected: [id], anchor: id)

        case .command:
            var selected = state.selected
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            return HistorySelectionState(selected: selected, anchor: id)

        case .shift:
            // No usable anchor (first click, or the anchored entry was deleted)
            // degrades to a plain click, which is what Finder does.
            guard let anchor = state.anchor, let start = order.firstIndex(of: anchor) else {
                return HistorySelectionState(selected: [id], anchor: id)
            }
            let range = start <= clicked ? start...clicked : clicked...start
            return HistorySelectionState(selected: Set(order[range]), anchor: anchor)
        }
    }

    /// A drag that starts on an unselected item selects just that item first;
    /// starting on an already-selected item drags the whole selection.
    public static func dragStart(on id: UUID,
                                 order: [UUID],
                                 state: HistorySelectionState) -> HistorySelectionState {
        if state.selected.contains(id) { return state }
        return click(on: id, modifier: .none, order: order, state: state)
    }
}
