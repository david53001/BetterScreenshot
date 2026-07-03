namespace BetterScreenshot.Editor;

/// <summary>
/// Snapshot-based undo/redo stacks (depth-capped). Push the state *before* a change (which clears redo); TryUndo
/// swaps the current state for the previous one (and makes the current redoable); TryRedo is the inverse.
/// </summary>
public sealed class UndoHistory<T>
{
    public const int MaxDepth = 50;

    private readonly List<T> _undo = new();
    private readonly List<T> _redo = new();

    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    public void Push(T snapshot)
    {
        _undo.Add(snapshot);
        if (_undo.Count > MaxDepth) _undo.RemoveAt(0);
        _redo.Clear();
    }

    public bool TryUndo(T current, out T previous)
    {
        if (_undo.Count == 0) { previous = default!; return false; }
        _redo.Add(current);
        previous = _undo[^1];
        _undo.RemoveAt(_undo.Count - 1);
        return true;
    }

    public bool TryRedo(T current, out T next)
    {
        if (_redo.Count == 0) { next = default!; return false; }
        _undo.Add(current);
        next = _redo[^1];
        _redo.RemoveAt(_redo.Count - 1);
        return true;
    }
}
