using System.Drawing;
using WF = System.Windows.Forms;

namespace BetterScreenshot.App.Tray;

/// <summary>Dark palette for the tray ContextMenuStrip, mirroring Theme.xaml (card/hover/hairline/text).</summary>
internal sealed class DarkMenuColors : WF.ProfessionalColorTable
{
    public static readonly Color Surface = Color.FromArgb(0x14, 0x14, 0x16);
    public static readonly Color Hover = Color.FromArgb(0x24, 0x24, 0x28);
    public static readonly Color Hairline = Color.FromArgb(0x2A, 0x2A, 0x2A);

    public override Color ToolStripDropDownBackground => Surface;
    public override Color ImageMarginGradientBegin => Surface;
    public override Color ImageMarginGradientMiddle => Surface;
    public override Color ImageMarginGradientEnd => Surface;
    public override Color MenuItemSelected => Hover;
    public override Color MenuItemSelectedGradientBegin => Hover;
    public override Color MenuItemSelectedGradientEnd => Hover;
    public override Color MenuItemBorder => Hover;
    public override Color MenuBorder => Hairline;
    public override Color SeparatorDark => Hairline;
    public override Color SeparatorLight => Hairline;
}

internal sealed class DarkMenuRenderer : WF.ToolStripProfessionalRenderer
{
    public DarkMenuRenderer() : base(new DarkMenuColors()) { }

    protected override void OnRenderItemText(WF.ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Enabled ? Color.FromArgb(0xF2, 0xF2, 0xF5) : Color.FromArgb(0x8A, 0x8A, 0x90);
        base.OnRenderItemText(e);
    }
}
