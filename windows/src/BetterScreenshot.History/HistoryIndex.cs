using System.Text.Json;
using System.Text.Json.Serialization;

namespace BetterScreenshot.History;

/// <summary>
/// Immutable, ordered (newest-first) index of history entries. Mutations return a new index plus the list of
/// evicted entries so the store can delete their owned files. Retention = 30-day age cap + count cap.
/// </summary>
public sealed class HistoryIndex : IEquatable<HistoryIndex>
{
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    private readonly List<HistoryEntry> _entries;

    public IReadOnlyList<HistoryEntry> Entries => _entries;

    public HistoryIndex(IEnumerable<HistoryEntry>? entries = null)
        => _entries = entries?.ToList() ?? new List<HistoryEntry>();

    /// <summary>Insert newest-first, then prune to the cap and 30-day age. Returns the new index + evicted entries.</summary>
    public (HistoryIndex Index, IReadOnlyList<HistoryEntry> Evicted) Adding(HistoryEntry entry, int cap, DateTime now)
    {
        var list = new List<HistoryEntry>(_entries.Count + 1) { entry };
        list.AddRange(_entries);
        return new HistoryIndex(list).Pruned(cap, now);
    }

    /// <summary>Keep only entries newer than 30 days AND within the newest <paramref name="cap"/>.</summary>
    public (HistoryIndex Index, IReadOnlyList<HistoryEntry> Evicted) Pruned(int cap, DateTime now)
    {
        var cutoff = now - MaxAge;
        var kept = new List<HistoryEntry>();
        var evicted = new List<HistoryEntry>();
        foreach (var e in _entries)
        {
            if (e.Date >= cutoff && kept.Count < cap) kept.Add(e);
            else evicted.Add(e);
        }
        return (new HistoryIndex(kept), evicted);
    }

    public (HistoryIndex Index, HistoryEntry? Removed) Removing(Guid id)
    {
        var removed = _entries.FirstOrDefault(e => e.Id == id);
        if (removed is null) return (this, null);
        return (new HistoryIndex(_entries.Where(e => e.Id != id)), removed);
    }

    public (HistoryIndex Index, IReadOnlyList<HistoryEntry> Removed) PrunedOfMissingFiles(Func<HistoryEntry, bool> exists)
    {
        var kept = new List<HistoryEntry>();
        var removed = new List<HistoryEntry>();
        foreach (var e in _entries)
        {
            if (exists(e)) kept.Add(e);
            else removed.Add(e);
        }
        return (new HistoryIndex(kept), removed);
    }

    public string ToJson() => JsonSerializer.Serialize(_entries, JsonOptions);

    /// <summary>Parse an index from JSON. Throws <see cref="JsonException"/> on malformed input (callers may start empty).</summary>
    public static HistoryIndex FromJson(string json)
    {
        var entries = JsonSerializer.Deserialize<List<HistoryEntry>>(json, JsonOptions)
                      ?? throw new JsonException("null history index");
        return new HistoryIndex(entries);
    }

    public bool Equals(HistoryIndex? other) => other is not null && _entries.SequenceEqual(other._entries);
    public override bool Equals(object? obj) => Equals(obj as HistoryIndex);
    public override int GetHashCode() => _entries.Aggregate(17, (h, e) => h * 31 + e.GetHashCode());
}
