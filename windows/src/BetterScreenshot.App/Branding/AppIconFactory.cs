using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace BetterScreenshot.App.Branding;

/// <summary>
/// Hand-draws the BetterScreenshot icon (a charcoal rounded square with a white camera glyph) at runtime via GDI+.
/// Entirely original vector-style drawing — no bundled bitmaps or screenshots. Used for the tray; Phase 8 replaces
/// this with a packaged multi-size .ico authored the same way.
/// </summary>
public static class AppIconFactory
{
    private static readonly Color Charcoal = Color.FromArgb(0x1C, 0x1C, 0x1C);
    private static readonly Color White = Color.FromArgb(0xF5, 0xF5, 0xF5);
    private static readonly Color RecordRed = Color.FromArgb(0xFF, 0x45, 0x3A);

    public static Icon CreateTrayIcon(bool recording) => Create(32, Charcoal, recording ? RecordRed : White);

    private static Icon Create(int size, Color bg, Color fg)
    {
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);

            using var bgBrush = new SolidBrush(bg);
            using var fgBrush = new SolidBrush(fg);

            FillRounded(g, bgBrush, new Rectangle(0, 0, size - 1, size - 1), size / 5);

            int bodyW = (int)(size * 0.60), bodyH = (int)(size * 0.40);
            int bodyX = (size - bodyW) / 2, bodyY = (int)(size * 0.34);

            // viewfinder hump
            g.FillRectangle(fgBrush, bodyX + bodyW / 6, bodyY - (int)(size * 0.07), bodyW / 4, (int)(size * 0.09));
            // camera body
            FillRounded(g, fgBrush, new Rectangle(bodyX, bodyY, bodyW, bodyH), size / 12);
            // lens (knocked out to the background color)
            int lens = (int)(size * 0.20);
            g.FillEllipse(bgBrush, (size - lens) / 2, bodyY + (bodyH - lens) / 2, lens, lens);
        }

        IntPtr hIcon = bmp.GetHicon();
        try
        {
            using var temp = Icon.FromHandle(hIcon);
            return (Icon)temp.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    private static void FillRounded(Graphics g, Brush brush, Rectangle r, int radius)
    {
        using var path = new GraphicsPath();
        int d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(brush, path);
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);
}
