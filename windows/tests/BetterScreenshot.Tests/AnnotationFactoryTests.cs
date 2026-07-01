using BetterScreenshot.App.Editor;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class AnnotationFactoryTests
{
    private static readonly AnnotationStyle S = AnnotationStyle.Default;

    [Fact]
    public void RectangleFromDragNormalizesFrame()
    {
        var a = AnnotationFactory.CreateDrag(EditorTool.Rectangle, new PxPoint(50, 40), new PxPoint(10, 10), S);
        var r = Assert.IsType<RectangleAnnotation>(a);
        Assert.Equal(new PxRect(10, 10, 40, 30), r.Frame);
        Assert.False(r.Filled);
    }

    [Fact]
    public void ArrowKeepsEndpoints()
    {
        var a = AnnotationFactory.CreateDrag(EditorTool.Arrow, new PxPoint(5, 6), new PxPoint(70, 80), S);
        var arrow = Assert.IsType<ArrowAnnotation>(a);
        Assert.Equal(new PxPoint(5, 6), arrow.Start);
        Assert.Equal(new PxPoint(70, 80), arrow.End);
    }

    [Theory]
    [InlineData(EditorTool.Select)]
    [InlineData(EditorTool.Text)]
    [InlineData(EditorTool.Counter)]
    [InlineData(EditorTool.Crop)]
    [InlineData(EditorTool.Blur)]
    public void NonDragShapeToolsReturnNull(EditorTool tool)
    {
        Assert.Null(AnnotationFactory.CreateDrag(tool, new PxPoint(0, 0), new PxPoint(10, 10), S));
    }
}
