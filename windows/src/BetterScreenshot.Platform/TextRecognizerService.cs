using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace BetterScreenshot.Platform;

/// <summary>
/// Capture-Text recognition: decodes QR codes (ZXing) and on-device text (Windows.Media.Ocr), then applies the
/// pure <see cref="RecognitionResolver"/> rule (QR wins over text). Everything runs locally — no network.
/// </summary>
public static class TextRecognizerService
{
    public static async Task<RecognitionResult> RecognizeAsync(BitmapSource image)
    {
        byte[] bgra = GetBgra(image, out int width, out int height);
        var qr = DecodeQr(bgra, width, height);
        var lines = await OcrLinesAsync(image);
        return RecognitionResolver.Resolve(qr, lines);
    }

    private static List<string> DecodeQr(byte[] bgra, int width, int height)
    {
        var found = new List<string>();
        try
        {
            var luminance = new ZXing.RGBLuminanceSource(bgra, width, height, ZXing.RGBLuminanceSource.BitmapFormat.BGRA32);
            var bitmap = new ZXing.BinaryBitmap(new ZXing.Common.HybridBinarizer(luminance));
            var reader = new ZXing.QrCode.QRCodeReader();
            var hints = new Dictionary<ZXing.DecodeHintType, object> { { ZXing.DecodeHintType.TRY_HARDER, true } };
            var result = reader.decode(bitmap, hints);
            if (result?.Text is { Length: > 0 } text) found.Add(text);
        }
        catch
        {
            // No QR code present (or undecodable) — fall through to OCR.
        }
        return found;
    }

    private static async Task<List<string>> OcrLinesAsync(BitmapSource image)
    {
        var engine = OcrEngine.TryCreateFromUserProfileLanguages();
        if (engine is null) return new List<string>();

        using var software = await ToSoftwareBitmapAsync(image);
        var result = await engine.RecognizeAsync(software);
        return result.Lines.Select(l => l.Text).ToList();
    }

    private static async Task<SoftwareBitmap> ToSoftwareBitmapAsync(BitmapSource image)
    {
        byte[] png = ImageIo.EncodePng(image);
        var stream = new InMemoryRandomAccessStream();
        var writer = new DataWriter(stream);
        writer.WriteBytes(png);
        await writer.StoreAsync();
        await writer.FlushAsync();
        writer.DetachStream();
        stream.Seek(0);

        var decoder = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(stream);
        var sb = await decoder.GetSoftwareBitmapAsync();
        if (sb.BitmapPixelFormat != BitmapPixelFormat.Bgra8 || sb.BitmapAlphaMode == BitmapAlphaMode.Straight)
            sb = SoftwareBitmap.Convert(sb, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        return sb;
    }

    private static byte[] GetBgra(BitmapSource source, out int width, out int height)
    {
        BitmapSource src = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        width = src.PixelWidth;
        height = src.PixelHeight;
        int stride = width * 4;
        var bytes = new byte[height * stride];
        src.CopyPixels(bytes, stride, 0);
        return bytes;
    }
}
