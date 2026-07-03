using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class TextRecognizerServiceTests
{
    private static BitmapSource MatrixToBitmap(ZXing.Common.BitMatrix matrix)
    {
        int w = matrix.Width, h = matrix.Height, stride = w * 4;
        var px = new byte[h * stride];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                byte v = matrix[x, y] ? (byte)0 : (byte)255; // set module = black
                int i = y * stride + x * 4;
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255;
            }
        return BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride);
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task DecodesQrPayloadAndQrWinsOverText()
    {
        const string payload = "https://github.com/david53001/BetterScreenshot";
        var matrix = new ZXing.QrCode.QRCodeWriter().encode(payload, ZXing.BarcodeFormat.QR_CODE, 260, 260);
        var image = MatrixToBitmap(matrix);

        var result = await TextRecognizerService.RecognizeAsync(image);

        Assert.Equal(RecognitionKind.Qr, result.Kind);
        Assert.Equal(payload, result.Value);
    }
}
