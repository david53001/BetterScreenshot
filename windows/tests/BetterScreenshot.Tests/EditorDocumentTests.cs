using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class EditorDocumentTests
{
    private static RectangleAnnotation Rect(double x, double y, double w, double h) =>
        new(Guid.NewGuid(), AnnotationStyle.Default, new PxRect(x, y, w, h), false);

    [Fact]
    public void AddAndCount()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        doc.Add(Rect(0, 0, 10, 10));
        Assert.Single(doc.Annotations);
    }

    [Fact]
    public void TopmostHitReturnsLastAdded()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        var a = Rect(0, 0, 50, 50);
        var b = Rect(0, 0, 50, 50);
        doc.Add(a);
        doc.Add(b);
        Assert.Equal(b.Id, doc.TopmostHit(new PxPoint(10, 10)));
    }

    [Fact]
    public void MoveById()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        var a = Rect(0, 0, 10, 10);
        doc.Add(a);
        doc.Move(a.Id, 5, 7);
        Assert.Equal(new PxRect(5, 7, 10, 10), doc.Annotations[0].BoundingBox());
    }

    [Fact]
    public void RemoveAndReorder()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        var a = Rect(0, 0, 10, 10);
        var b = Rect(20, 20, 10, 10);
        doc.Add(a);
        doc.Add(b);
        doc.BringToFront(a.Id);
        Assert.Equal(a.Id, doc.Annotations[^1].Id);
        doc.SendToBack(a.Id);
        Assert.Equal(a.Id, doc.Annotations[0].Id);
        Assert.True(doc.Remove(a.Id));
        Assert.Single(doc.Annotations);
    }

    [Fact]
    public void IdsIntersectingReturnsOnlyOverlapping()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        var a = Rect(0, 0, 10, 10);
        var b = Rect(50, 50, 10, 10);
        doc.Add(a);
        doc.Add(b);
        var ids = doc.IdsIntersecting(new PxRect(0, 0, 20, 20));
        Assert.Contains(a.Id, ids);
        Assert.DoesNotContain(b.Id, ids);
    }

    [Fact]
    public void IdsIntersectingReturnsAllWhenMarqueeCoversEverything()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        doc.Add(Rect(0, 0, 10, 10));
        doc.Add(Rect(50, 50, 10, 10));
        Assert.Equal(2, doc.IdsIntersecting(new PxRect(0, 0, 100, 100)).Count);
    }

    [Fact]
    public void CropResizesBaseAndOffsetsAnnotations()
    {
        var doc = new EditorDocument(new PxSize(200, 200));
        doc.Add(Rect(50, 60, 10, 10));
        var cropped = doc.Cropped(new PxRect(40, 50, 100, 100));
        Assert.Equal(new PxSize(100, 100), cropped.Size);
        Assert.Equal(new PxRect(10, 10, 10, 10), cropped.Annotations[0].BoundingBox());
    }
}

public class AnnotationTests
{
    private static readonly AnnotationStyle S = AnnotationStyle.Default;

    [Fact]
    public void CounterBoundingBoxIsSquareAtOrigin()
    {
        var c = new CounterAnnotation(Guid.NewGuid(), S, 1, new PxPoint(10, 20));
        var bb = c.BoundingBox();
        Assert.Equal(bb.Width, bb.Height);
        Assert.Equal(10, bb.X);
        Assert.Equal(20, bb.Y);
        Assert.Equal(Math.Max(28, 24 * 1.6), bb.Width, 6); // 38.4
    }

    [Fact]
    public void CenteredFactoryCentersBadgeOnPoint()
    {
        var c = CounterAnnotation.Centered(new PxPoint(100, 100), 1, S);
        Assert.Equal(100, c.BoundingBox().Center.X, 6);
        Assert.Equal(100, c.BoundingBox().Center.Y, 6);
    }

    [Fact]
    public void NextCounterNumberCountsCountersOnly()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        doc.Add(new CounterAnnotation(Guid.NewGuid(), S, 1, new PxPoint(0, 0)));
        doc.Add(new RectangleAnnotation(Guid.NewGuid(), S, new PxRect(0, 0, 10, 10), false));
        doc.Add(new CounterAnnotation(Guid.NewGuid(), S, 2, new PxPoint(0, 0)));
        Assert.Equal(3, doc.NextCounterNumber());
    }

    [Fact]
    public void TextLongerStringHasWiderBox()
    {
        var t1 = new TextAnnotation(Guid.NewGuid(), S, "hi", new PxPoint(0, 0));
        var t2 = new TextAnnotation(Guid.NewGuid(), S, "hello world", new PxPoint(0, 0));
        Assert.True(t2.BoundingBox().Width > t1.BoundingBox().Width);
    }

    [Fact]
    public void TextMoveOffsetsOrigin()
    {
        var t = new TextAnnotation(Guid.NewGuid(), S, "x", new PxPoint(5, 5));
        var moved = (TextAnnotation)t.MovedBy(3, 4);
        Assert.Equal(new PxPoint(8, 9), moved.Origin);
    }

    [Fact]
    public void RectangleBoundingBoxAndMove()
    {
        var r = new RectangleAnnotation(Guid.NewGuid(), S, new PxRect(1, 2, 3, 4), false);
        Assert.Equal(new PxRect(1, 2, 3, 4), r.BoundingBox());
        var m = (RectangleAnnotation)r.MovedBy(10, 10);
        Assert.Equal(new PxRect(11, 12, 3, 4), m.Frame);
    }

    [Fact]
    public void EllipseHitTestUsesBoundingBox()
    {
        var e = new EllipseAnnotation(Guid.NewGuid(), S, new PxRect(0, 0, 20, 20));
        Assert.True(e.HitTest(new PxPoint(10, 10)));
        Assert.True(e.HitTest(new PxPoint(-3, -3)));   // within 6px slop
        Assert.False(e.HitTest(new PxPoint(-10, -10))); // outside slop
    }

    [Fact]
    public void LineBoundingBoxSpansEndpoints()
    {
        var l = new LineAnnotation(Guid.NewGuid(), S, new PxPoint(10, 50), new PxPoint(60, 20));
        Assert.Equal(new PxRect(10, 20, 50, 30), l.BoundingBox());
    }
}
