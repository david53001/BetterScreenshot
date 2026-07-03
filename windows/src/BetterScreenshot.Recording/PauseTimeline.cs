namespace BetterScreenshot.Recording;

/// <summary>
/// Pure bookkeeping for gapless pause/resume. Accumulates the timeline gap introduced by each pause and, given a
/// raw presentation timestamp, returns the adjusted timestamp so the output file has no gap. Time is in generic
/// integer units (ticks/PTS); the engine picks the timescale.
/// </summary>
public struct PauseTimeline : IEquatable<PauseTimeline>
{
    /// <summary>Total accumulated gap to subtract from post-resume timestamps.</summary>
    public long Offset { get; private set; }

    /// <summary>
    /// On the first sample after a resume, record the gap = firstAfter − lastBefore − frameDuration. A gap of ≤0
    /// (the resumed frame is within one frame duration) is ignored, keeping the timeline monotonic.
    /// </summary>
    public void Resume(long lastPtsBeforePause, long firstPtsAfterResume, long frameDuration)
    {
        long gap = firstPtsAfterResume - lastPtsBeforePause - frameDuration;
        if (gap > 0) Offset += gap;
    }

    public long Adjusted(long pts) => pts - Offset;

    public bool Equals(PauseTimeline other) => Offset == other.Offset;
    public override bool Equals(object? obj) => obj is PauseTimeline p && Equals(p);
    public override int GetHashCode() => Offset.GetHashCode();
}
