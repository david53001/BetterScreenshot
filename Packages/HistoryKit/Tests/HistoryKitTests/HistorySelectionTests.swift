import TestKit
import Foundation
@testable import HistoryKit

// A fixed newest-first order, mirroring HistoryIndex.entries.
private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
private let order = [a, b, c, d]

private func state(_ selected: Set<UUID>, anchor: UUID?) -> HistorySelectionState {
    HistorySelectionState(selected: selected, anchor: anchor)
}

let historySelectionTests: [TestCase] = [
    TestCase("plainClickSelectsOnlyThatItem") { t in
        let s = HistorySelection.click(on: c, modifier: .none, order: order,
                                       state: state([a, b], anchor: a))
        t.equal(s.selected, [c])
        t.equal(s.anchor, c)
    },
    TestCase("commandClickAddsToSelection") { t in
        let s = HistorySelection.click(on: c, modifier: .command, order: order,
                                       state: state([a], anchor: a))
        t.equal(s.selected, [a, c])
        t.equal(s.anchor, c)
    },
    TestCase("commandClickTogglesOffWhenAlreadySelected") { t in
        let s = HistorySelection.click(on: a, modifier: .command, order: order,
                                       state: state([a, c], anchor: c))
        t.equal(s.selected, [c])
        t.equal(s.anchor, a)
    },
    TestCase("shiftClickSelectsRangeForwardFromAnchor") { t in
        let s = HistorySelection.click(on: c, modifier: .shift, order: order,
                                       state: state([a], anchor: a))
        t.equal(s.selected, [a, b, c])
        t.equal(s.anchor, a, "the anchor stays put so the range can be re-dragged")
    },
    TestCase("shiftClickSelectsRangeBackwardFromAnchor") { t in
        let s = HistorySelection.click(on: a, modifier: .shift, order: order,
                                       state: state([c], anchor: c))
        t.equal(s.selected, [a, b, c])
        t.equal(s.anchor, c)
    },
    TestCase("shiftClickReplacesThePreviousRange") { t in
        // Anchor at a, previously ranged out to d; shift-clicking b shrinks it.
        let s = HistorySelection.click(on: b, modifier: .shift, order: order,
                                       state: state([a, b, c, d], anchor: a))
        t.equal(s.selected, [a, b])
        t.equal(s.anchor, a)
    },
    TestCase("shiftClickWithoutAnchorActsAsAPlainClick") { t in
        let s = HistorySelection.click(on: c, modifier: .shift, order: order,
                                       state: state([], anchor: nil))
        t.equal(s.selected, [c])
        t.equal(s.anchor, c)
    },
    TestCase("shiftClickWithAStaleAnchorActsAsAPlainClick") { t in
        // The anchored entry was deleted since it was clicked.
        let s = HistorySelection.click(on: c, modifier: .shift, order: order,
                                       state: state([], anchor: UUID()))
        t.equal(s.selected, [c])
        t.equal(s.anchor, c)
    },
    TestCase("clickOnAnUnknownIDLeavesTheStateUnchanged") { t in
        let before = state([a], anchor: a)
        let s = HistorySelection.click(on: UUID(), modifier: .none, order: order, state: before)
        t.equal(s, before)
    },
    TestCase("dragOnAnUnselectedItemSelectsItAlone") { t in
        let s = HistorySelection.dragStart(on: d, order: order, state: state([a, b], anchor: a))
        t.equal(s.selected, [d])
        t.equal(s.anchor, d)
    },
    TestCase("dragOnASelectedItemKeepsTheWholeSelection") { t in
        let before = state([a, b], anchor: a)
        let s = HistorySelection.dragStart(on: b, order: order, state: before)
        t.equal(s, before)
    },
]
