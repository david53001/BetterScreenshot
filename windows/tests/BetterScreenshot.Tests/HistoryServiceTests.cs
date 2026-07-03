using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.History;
using BetterScreenshot.History;
using Xunit;

namespace BetterScreenshot.Tests;

public class HistoryServiceTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "bs-histsvc-" + Guid.NewGuid().ToString("N"));
    private bool _enabled = true;

    public void Dispose()
    {
        try { if (Directory.Exists(_dir)) Directory.Delete(_dir, true); } catch { }
    }

    private HistoryService NewService(int cap = 50) => new(_dir, () => cap, () => _enabled);

    private static BitmapSource Bmp(int w = 60, int h = 40)
    {
        int stride = w * 4;
        var px = new byte[h * stride];
        for (int i = 0; i < px.Length; i += 4) { px[i] = 0; px[i + 1] = 0; px[i + 2] = 200; px[i + 3] = 255; }
        var src = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride);
        src.Freeze();
        return src;
    }

    private string DummyRecording()
    {
        Directory.CreateDirectory(_dir);
        var path = Path.Combine(_dir, "rec-" + Guid.NewGuid().ToString("N") + ".mp4");
        File.WriteAllBytes(path, new byte[] { 0, 1, 2, 3 });
        return path;
    }

    [Fact]
    public void RecordScreenshotPersistsAndReturnsId()
    {
        var svc = NewService();
        var id = svc.RecordScreenshot(Bmp());
        Assert.NotNull(id);
        Assert.Single(svc.Entries);
        var entry = svc.Entry(id!.Value)!;
        Assert.Equal(HistoryKind.Screenshot, entry.Kind);
        Assert.True(File.Exists(svc.ImagePath(entry)!));
        Assert.True(File.Exists(svc.ThumbPath(entry)));
    }

    [Fact]
    public void RecordScreenshotIsNoOpWhenDisabled()
    {
        _enabled = false;
        var svc = NewService();
        var id = svc.RecordScreenshot(Bmp());
        Assert.Null(id);
        Assert.Empty(svc.Entries);
    }

    [Fact]
    public void RecordRecordingStoresReferenceNotCopy()
    {
        var svc = NewService();
        var rec = DummyRecording();
        var id = svc.RecordRecording(rec, Bmp());
        Assert.NotNull(id);
        var entry = svc.Entry(id!.Value)!;
        Assert.Equal(HistoryKind.Recording, entry.Kind);
        Assert.Equal(rec, svc.SavedFilePath(entry));
        Assert.True(svc.SavedFileExists(entry));
        Assert.Null(svc.ImagePath(entry));
    }

    [Fact]
    public void PopRestorableReturnsNewestClosedThenSkipsDeleted()
    {
        var svc = NewService();
        var a = svc.RecordScreenshot(Bmp())!.Value;
        var b = svc.RecordScreenshot(Bmp())!.Value;
        var c = svc.RecordScreenshot(Bmp())!.Value;
        svc.NoteClosed(a);
        svc.NoteClosed(b);
        svc.NoteClosed(c);
        svc.Delete(b); // b no longer restorable

        Assert.Equal(c, svc.PopRestorable()!.Id); // newest survivor first
        Assert.Equal(a, svc.PopRestorable()!.Id); // b skipped
        Assert.Null(svc.PopRestorable());          // drained
    }

    [Fact]
    public void LoadImageRoundTripsScreenshotDimensions()
    {
        var svc = NewService();
        var id = svc.RecordScreenshot(Bmp(80, 50))!.Value;
        var loaded = svc.LoadImage(svc.Entry(id)!);
        Assert.NotNull(loaded);
        Assert.Equal(80, loaded!.PixelWidth);
        Assert.Equal(50, loaded.PixelHeight);
    }

    [Fact]
    public void DeleteRemovesEntryAndOwnedFiles()
    {
        var svc = NewService();
        var id = svc.RecordScreenshot(Bmp())!.Value;
        var image = svc.ImagePath(svc.Entry(id)!)!;
        svc.Delete(id);
        Assert.Empty(svc.Entries);
        Assert.False(File.Exists(image));
    }

    [Fact]
    public void ClearAllEmptiesHistory()
    {
        var svc = NewService();
        svc.RecordScreenshot(Bmp());
        svc.RecordScreenshot(Bmp());
        svc.ClearAll();
        Assert.Empty(svc.Entries);
    }

    [Fact]
    public void ExplorerSelectArgsQuotesPath()
    {
        Assert.Equal("/select,\"C:\\a b\\shot.png\"", HistoryService.ExplorerSelectArgs("C:\\a b\\shot.png"));
    }
}
