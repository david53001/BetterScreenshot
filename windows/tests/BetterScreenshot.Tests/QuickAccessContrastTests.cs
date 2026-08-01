using BetterScreenshot.App.Overlays;

namespace BetterScreenshot.Tests;

/// <summary>The pure half of the Quick Access auto-contrast: luminance averaging + the light/dark decision.</summary>
public class QuickAccessContrastTests
{
    private static byte[] SolidBgra(byte r, byte g, byte b, int w, int h)
    {
        var px = new byte[w * h * 4];
        for (int i = 0; i < px.Length; i += 4)
        {
            px[i] = b;
            px[i + 1] = g;
            px[i + 2] = r;
            px[i + 3] = 255;
        }
        return px;
    }

    [Fact]
    public void White_strip_reads_as_light_background()
    {
        double lum = QuickAccessContrast.AverageLuminance(SolidBgra(255, 255, 255, 8, 4), 8 * 4, 8, 4);
        Assert.Equal(1.0, lum, 3);
        Assert.True(QuickAccessContrast.IsLightBackground(lum));
    }

    [Fact]
    public void Black_strip_reads_as_dark_background()
    {
        double lum = QuickAccessContrast.AverageLuminance(SolidBgra(0, 0, 0, 8, 4), 8 * 4, 8, 4);
        Assert.Equal(0.0, lum, 3);
        Assert.False(QuickAccessContrast.IsLightBackground(lum));
    }

    [Fact]
    public void Half_white_half_black_averages_to_mid_and_reads_dark()
    {
        // Row 0 white, row 1 black → mean luminance ≈ 0.5, which stays below the light threshold.
        int w = 4, h = 2, stride = w * 4;
        var px = new byte[stride * h];
        for (int x = 0; x < w; x++)
        {
            int i = x * 4; // row 0 only
            px[i] = 255;
            px[i + 1] = 255;
            px[i + 2] = 255;
            px[i + 3] = 255;
        }
        double lum = QuickAccessContrast.AverageLuminance(px, stride, w, h);
        Assert.InRange(lum, 0.45, 0.55);
        Assert.False(QuickAccessContrast.IsLightBackground(lum));
    }

    [Fact]
    public void Stride_padding_is_respected()
    {
        // 2px-wide row with 8 bytes of trailing padding per row must not be counted.
        int w = 2, h = 2, stride = w * 4 + 8;
        var px = new byte[stride * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * stride + x * 4;
                px[i] = 255; px[i + 1] = 255; px[i + 2] = 255; px[i + 3] = 255; // white pixels only
            }
        Assert.Equal(1.0, QuickAccessContrast.AverageLuminance(px, stride, w, h), 3);
    }

    [Theory]
    [InlineData(0.90, true)]
    [InlineData(0.60, true)]
    [InlineData(0.58, false)] // boundary: not strictly greater than the threshold
    [InlineData(0.30, false)]
    public void Threshold_decides_light_vs_dark(double luminance, bool expectedLight) =>
        Assert.Equal(expectedLight, QuickAccessContrast.IsLightBackground(luminance));

    [Fact]
    public void Empty_buffer_is_treated_as_dark()
    {
        Assert.Equal(0.0, QuickAccessContrast.AverageLuminance(Array.Empty<byte>(), 0, 0, 0), 3);
        Assert.False(QuickAccessContrast.IsLightBackground(0.0));
    }
}
