using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class UndoHistoryTests
{
    [Fact]
    public void PushThenUndoReturnsPrevious()
    {
        var h = new UndoHistory<string>();
        h.Push("a");
        Assert.True(h.CanUndo);
        Assert.True(h.TryUndo("b", out var prev));
        Assert.Equal("a", prev);
        Assert.True(h.CanRedo);
    }

    [Fact]
    public void RedoReturnsTheUndoneState()
    {
        var h = new UndoHistory<string>();
        h.Push("a");
        h.TryUndo("b", out _);
        Assert.True(h.TryRedo("a", out var next));
        Assert.Equal("b", next);
    }

    [Fact]
    public void PushClearsRedo()
    {
        var h = new UndoHistory<string>();
        h.Push("a");
        h.TryUndo("b", out _);
        Assert.True(h.CanRedo);
        h.Push("b");
        Assert.False(h.CanRedo);
    }

    [Fact]
    public void UndoOnEmptyReturnsFalse()
    {
        var h = new UndoHistory<string>();
        Assert.False(h.TryUndo("x", out _));
    }

    [Fact]
    public void DepthIsCapped()
    {
        var h = new UndoHistory<int>();
        for (int i = 0; i < UndoHistory<int>.MaxDepth + 10; i++) h.Push(i);
        int count = 0;
        while (h.TryUndo(-1, out _)) count++;
        Assert.Equal(UndoHistory<int>.MaxDepth, count);
    }
}
