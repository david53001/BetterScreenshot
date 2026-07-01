using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;

namespace BetterScreenshot.App.Editor;

/// <summary>Builds a drag-created annotation (shape tools) from the start/end points and current style.</summary>
public static class AnnotationFactory
{
    public static IAnnotation? CreateDrag(EditorTool tool, PxPoint start, PxPoint end, AnnotationStyle style)
    {
        var frame = SelectionMath.Normalize(start, end);
        return tool switch
        {
            EditorTool.Arrow => new ArrowAnnotation(Guid.NewGuid(), style, start, end),
            EditorTool.Line => new LineAnnotation(Guid.NewGuid(), style, start, end),
            EditorTool.Rectangle => new RectangleAnnotation(Guid.NewGuid(), style, frame, false),
            EditorTool.FilledRectangle => new FilledRectangleAnnotation(Guid.NewGuid(), style, frame),
            EditorTool.Ellipse => new EllipseAnnotation(Guid.NewGuid(), style, frame),
            _ => null,
        };
    }
}
