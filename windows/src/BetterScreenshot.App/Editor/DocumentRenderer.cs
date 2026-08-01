using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// Flattens an <see cref="EditorDocument"/> (base image + annotations + optional in-progress preview) to a
/// <see cref="BitmapSource"/> using WPF drawing, top-left origin (no context flip — WPF is natively top-left).
/// </summary>
public static class DocumentRenderer
{
    private static readonly FontFamily Font = new("Segoe UI");

    /// <summary>Font family + weight used for text annotations, exposed so the live editing box can match exactly.</summary>
    public static FontFamily TextFont => Font;
    public static FontWeight TextWeight => FontWeights.Bold;

    /// <summary>Padding between text and the edge of its optional background chip. Shared with the editing box so
    /// the live preview and the flattened result line up.</summary>
    public const double TextChipPadX = 6;
    public const double TextChipPadY = 2;

    public static BitmapSource Render(EditorDocument doc, BitmapSource baseImage, IAnnotation? preview = null)
    {
        int w = (int)Math.Round(doc.Size.Width);
        int h = (int)Math.Round(doc.Size.Height);

        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawImage(baseImage, new Rect(0, 0, w, h));
            foreach (var annotation in doc.Annotations) Draw(dc, annotation);
            if (preview is not null) Draw(dc, preview);
        }

        var rtb = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(visual);
        rtb.Freeze();
        return rtb;
    }

    private static void Draw(DrawingContext dc, IAnnotation annotation)
    {
        switch (annotation)
        {
            case ArrowAnnotation a:
            {
                double headLen = Math.Max(12, a.Style.LineWidth * 3);
                var shaftEnd = ArrowGeometry.ShaftEnd(a.Start, a.End, headLen);
                dc.DrawLine(RoundPen(a.Style), Pt(a.Start), Pt(shaftEnd));
                var (left, right) = ArrowGeometry.HeadWings(a.Start, a.End, headLen);
                var head = new StreamGeometry();
                using (var g = head.Open())
                {
                    g.BeginFigure(Pt(a.End), true, true);
                    g.LineTo(Pt(left), true, false);
                    g.LineTo(Pt(right), true, false);
                }
                dc.DrawGeometry(Solid(a.Style.StrokeColor), null, head);
                break;
            }
            case LineAnnotation l:
                dc.DrawLine(RoundPen(l.Style), Pt(l.Start), Pt(l.End));
                break;
            case FilledRectangleAnnotation fr:
                dc.DrawRectangle(Solid(fr.Style.FillColor), null, RectOf(fr.Frame));
                break;
            case RectangleAnnotation r:
                dc.DrawRectangle(r.Filled ? Solid(r.Style.FillColor) : null, Stroke(r.Style), RectOf(r.Frame));
                break;
            case EllipseAnnotation e:
            {
                var rect = RectOf(e.Frame);
                dc.DrawEllipse(null, Stroke(e.Style), new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2), rect.Width / 2, rect.Height / 2);
                break;
            }
            case TextAnnotation t:
            {
                var ft = FormatText(t.Text, t.Style.FontSize, Solid(t.Style.StrokeColor), FontWeights.Bold);
                if (t.Style.TextBackground is { } bg)
                {
                    var chip = new Rect(t.Origin.X - TextChipPadX, t.Origin.Y - TextChipPadY,
                        ft.Width + 2 * TextChipPadX, ft.Height + 2 * TextChipPadY);
                    dc.DrawRoundedRectangle(Solid(bg), null, chip, 4, 4);
                }
                dc.DrawText(ft, Pt(t.Origin));
                break;
            }
            case CounterAnnotation c:
            {
                double d = c.Diameter;
                var center = new Point(c.Origin.X + d / 2, c.Origin.Y + d / 2);
                dc.DrawEllipse(Solid(c.Style.StrokeColor), null, center, d / 2, d / 2);
                var ft = FormatText(c.Number.ToString(CultureInfo.InvariantCulture), d * 0.55, Brushes.White, FontWeights.Bold);
                dc.DrawText(ft, new Point(center.X - ft.Width / 2, center.Y - ft.Height / 2));
                break;
            }
            case PixelateAnnotation px when px.Patch is { } patch:
                dc.DrawImage(ImageConvert.ToBitmapSource(patch), RectOf(px.Frame));
                break;
            case BlurAnnotation bl when bl.Patch is { } patch:
                dc.DrawImage(ImageConvert.ToBitmapSource(patch), RectOf(bl.Frame));
                break;
        }
    }

    private static Pen RoundPen(AnnotationStyle style) => new(Solid(style.StrokeColor), style.LineWidth)
    {
        StartLineCap = PenLineCap.Round,
        EndLineCap = PenLineCap.Round,
        LineJoin = PenLineJoin.Round,
    };

    private static Pen Stroke(AnnotationStyle style) => new(Solid(style.StrokeColor), style.LineWidth);

    private static FormattedText FormatText(string text, double emSize, Brush brush, FontWeight weight) =>
        new(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface(Font, FontStyles.Normal, weight, FontStretches.Normal), emSize, brush, 1.0);

    private static Brush Solid(RGBAColor c) =>
        new SolidColorBrush(Color.FromArgb((byte)(c.A * 255), (byte)(c.R * 255), (byte)(c.G * 255), (byte)(c.B * 255)));

    private static Point Pt(PxPoint p) => new(p.X, p.Y);
    private static Rect RectOf(PxRect r) => new(r.X, r.Y, r.Width, r.Height);
}
