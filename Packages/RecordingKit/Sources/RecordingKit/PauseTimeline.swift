import CoreMedia

/// Accumulates the time skipped across pause/resume boundaries so the writer can
/// retime post-resume sample buffers into a gap-free, monotonic timeline.
public struct PauseTimeline: Equatable {
    private var offset: CMTime

    public init() { offset = .zero }

    /// Total accumulated offset to subtract from raw sample PTS.
    public var currentOffset: CMTime { offset }

    /// Extend the offset by the silent gap between the last frame appended before
    /// pausing and the first frame after resuming. A zero/negative gap is ignored.
    public mutating func resume(lastPTSBeforePause: CMTime,
                                firstPTSAfterResume: CMTime,
                                frameDuration: CMTime) {
        let gap = firstPTSAfterResume - lastPTSBeforePause - frameDuration
        if gap > .zero { offset = offset + gap }
    }

    /// Raw PTS mapped into the gap-free timeline.
    public func adjusted(_ pts: CMTime) -> CMTime { pts - offset }
}
