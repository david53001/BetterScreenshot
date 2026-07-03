namespace BetterScreenshot.History;

/// <summary>
/// In-memory LIFO of recently ✕-closed / evicted overlay ids for "Restore Recently Closed". Depth-capped at 5,
/// never persisted. Re-pushing an id moves it to the top; popping returns the newest first.
/// </summary>
public sealed class RestoreStack
{
    public const int Depth = 5;

    private readonly List<Guid> _items = new(); // last element = newest (top)

    public bool IsEmpty => _items.Count == 0;

    public void Push(Guid id)
    {
        _items.Remove(id);          // re-push moves to top
        _items.Add(id);
        if (_items.Count > Depth) _items.RemoveAt(0); // drop oldest
    }

    public Guid? Pop()
    {
        if (_items.Count == 0) return null;
        var id = _items[^1];
        _items.RemoveAt(_items.Count - 1);
        return id;
    }

    /// <summary>
    /// Pops the newest id whose entry still exists (per <paramref name="exists"/>), discarding any popped ids that
    /// have since been deleted/evicted from history. Returns null (and drains the stack) if none remain restorable.
    /// </summary>
    public Guid? PopRestorable(Func<Guid, bool> exists)
    {
        while (_items.Count > 0)
        {
            var id = _items[^1];
            _items.RemoveAt(_items.Count - 1);
            if (exists(id)) return id;
        }
        return null;
    }
}
