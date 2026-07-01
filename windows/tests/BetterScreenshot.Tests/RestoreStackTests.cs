using BetterScreenshot.History;
using Xunit;

namespace BetterScreenshot.Tests;

public class RestoreStackTests
{
    [Fact]
    public void PopReturnsNewestFirst()
    {
        var s = new RestoreStack();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        s.Push(a);
        s.Push(b);
        Assert.Equal(b, s.Pop());
        Assert.Equal(a, s.Pop());
        Assert.Null(s.Pop());
    }

    [Fact]
    public void IsEmptyTracksContents()
    {
        var s = new RestoreStack();
        Assert.True(s.IsEmpty);
        s.Push(Guid.NewGuid());
        Assert.False(s.IsEmpty);
        s.Pop();
        Assert.True(s.IsEmpty);
    }

    [Fact]
    public void DepthCapDropsOldest()
    {
        var s = new RestoreStack();
        var ids = new List<Guid>();
        for (int k = 0; k < RestoreStack.Depth + 1; k++)
        {
            var id = Guid.NewGuid();
            ids.Add(id);
            s.Push(id);
        }
        // Newest 5 remain, popped newest-first; the very first pushed id was dropped.
        for (int k = ids.Count - 1; k >= 1; k--)
            Assert.Equal(ids[k], s.Pop());
        Assert.Null(s.Pop()); // ids[0] was dropped
    }

    [Fact]
    public void RepushMovesIdToTop()
    {
        var s = new RestoreStack();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        s.Push(a);
        s.Push(b);
        s.Push(a); // move a to top
        Assert.Equal(a, s.Pop());
        Assert.Equal(b, s.Pop());
    }
}
