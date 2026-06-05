import Foundation

/// In-memory LIFO of recently ✕-closed/evicted overlays, identified by their
/// history entry IDs. Depth-capped; never persisted (cleared on quit by virtue
/// of living in memory).
public struct RestoreStack: Equatable {
    public static let depth = 5
    private var ids: [UUID] = []   // last = newest

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }

    /// Push a newly-closed overlay. Re-pushing an id moves it to the top.
    public mutating func push(_ id: UUID) {
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > Self.depth { ids.removeFirst(ids.count - Self.depth) }
    }

    /// Pop the most recently closed id.
    public mutating func pop() -> UUID? {
        ids.popLast()
    }
}
