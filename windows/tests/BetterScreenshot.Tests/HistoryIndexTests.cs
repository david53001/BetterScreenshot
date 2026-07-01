using System.Text.Json;
using BetterScreenshot.History;
using Xunit;

namespace BetterScreenshot.Tests;

public class HistoryIndexTests
{
    private static HistoryEntry Shot(DateTime date, Guid? id = null) => new()
    {
        Id = id ?? Guid.NewGuid(),
        Kind = HistoryKind.Screenshot,
        Date = date,
        ImageFile = "a.png",
        ThumbFile = "a-thumb.jpg",
    };

    private static readonly DateTime Now = new(2026, 6, 1, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void AddingInsertsNewestFirst()
    {
        var idx = new HistoryIndex();
        var (i1, _) = idx.Adding(Shot(Now.AddMinutes(-2)), cap: 10, now: Now);
        var newest = Shot(Now);
        var (i2, _) = i1.Adding(newest, cap: 10, now: Now);
        Assert.Equal(newest.Id, i2.Entries[0].Id);
        Assert.Equal(2, i2.Entries.Count);
    }

    [Fact]
    public void CountCapEvictsOldest()
    {
        // Entries are newest-FIRST by insertion order; the first one added (oldest) is evicted at the cap.
        var idx = new HistoryIndex();
        HistoryEntry? oldest = null;
        for (int k = 0; k < 4; k++)
        {
            var e = Shot(Now.AddMinutes(-(3 - k))); // k=0 oldest date, added first
            if (k == 0) oldest = e;
            (idx, _) = idx.Adding(e, cap: 3, now: Now);
        }
        Assert.Equal(3, idx.Entries.Count);
        Assert.DoesNotContain(idx.Entries, e => e.Id == oldest!.Id);
    }

    [Fact]
    public void EntriesOlderThan30DaysArePruned()
    {
        var idx = new HistoryIndex(new[] { Shot(Now.AddDays(-31)) });
        var (pruned, evicted) = idx.Pruned(cap: 100, now: Now);
        Assert.Empty(pruned.Entries);
        Assert.Single(evicted);
    }

    [Fact]
    public void Exactly30DayOldEntrySurvives()
    {
        var idx = new HistoryIndex(new[] { Shot(Now.AddDays(-30)) });
        var (pruned, _) = idx.Pruned(cap: 100, now: Now);
        Assert.Single(pruned.Entries);
    }

    [Fact]
    public void RemovingReturnsEntryAndUnknownIsNoOp()
    {
        var e = Shot(Now);
        var idx = new HistoryIndex(new[] { e });
        var (after, removed) = idx.Removing(e.Id);
        Assert.Equal(e.Id, removed!.Id);
        Assert.Empty(after.Entries);

        var (same, none) = idx.Removing(Guid.NewGuid());
        Assert.Null(none);
        Assert.Single(same.Entries);
    }

    [Fact]
    public void PrunedOfMissingFilesDropsOnlyMissing()
    {
        var present = Shot(Now, Guid.NewGuid());
        var missing = Shot(Now, Guid.NewGuid());
        var idx = new HistoryIndex(new[] { present, missing });
        var (kept, removed) = idx.PrunedOfMissingFiles(e => e.Id == present.Id);
        Assert.Single(kept.Entries);
        Assert.Equal(present.Id, kept.Entries[0].Id);
        Assert.Single(removed);
        Assert.Equal(missing.Id, removed[0].Id);
    }

    [Fact]
    public void JsonRoundTrip()
    {
        var idx = new HistoryIndex(new[] { Shot(Now), Shot(Now.AddMinutes(-5)) });
        var round = HistoryIndex.FromJson(idx.ToJson());
        Assert.Equal(idx, round);
    }

    [Fact]
    public void CorruptJsonThrows()
    {
        Assert.ThrowsAny<JsonException>(() => HistoryIndex.FromJson("{ not json ]"));
    }
}
