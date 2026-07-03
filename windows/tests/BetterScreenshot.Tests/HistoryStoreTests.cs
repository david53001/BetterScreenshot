using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.History;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class HistoryStoreTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "bs-hist-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { if (Directory.Exists(_dir)) Directory.Delete(_dir, true); } catch { }
    }

    private static byte[] Png(int w = 60, int h = 40)
    {
        int stride = w * 4;
        var px = new byte[h * stride];
        for (int i = 0; i < px.Length; i += 4) { px[i] = 0; px[i + 1] = 0; px[i + 2] = 200; px[i + 3] = 255; }
        return ImageIo.EncodePng(BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride));
    }

    private string DummyRecording()
    {
        var path = Path.Combine(_dir, "rec-" + Guid.NewGuid().ToString("N") + ".mp4");
        Directory.CreateDirectory(_dir);
        File.WriteAllBytes(path, new byte[] { 0, 1, 2, 3 });
        return path;
    }

    [Fact]
    public void AddScreenshotWritesCopyThumbAndIndex()
    {
        var store = new HistoryStore(_dir, cap: 50);
        var entry = store.AddScreenshot(Png(), 50);
        Assert.NotNull(entry);
        Assert.True(File.Exists(store.ImagePath(entry!)!));
        Assert.True(File.Exists(store.ThumbPath(entry)));
        Assert.True(File.Exists(Path.Combine(_dir, "history.json")));
    }

    [Fact]
    public void AddRecordingStoresReferenceNotCopy()
    {
        var store = new HistoryStore(_dir, 50);
        var rec = DummyRecording();
        var entry = store.AddRecording(rec, Png(), 50);
        Assert.NotNull(entry);
        Assert.Equal(rec, entry!.FilePath);
        Assert.True(File.Exists(store.ThumbPath(entry)));
        Assert.True(File.Exists(rec)); // original untouched
        Assert.Null(entry.ImageFile);
    }

    [Fact]
    public void ReloadRoundTripsIndex()
    {
        var store = new HistoryStore(_dir, 50);
        var a = store.AddScreenshot(Png(), 50)!;
        var b = store.AddScreenshot(Png(), 50)!;
        var reloaded = new HistoryStore(_dir, 50);
        Assert.Equal(2, reloaded.Index.Entries.Count);
        Assert.Equal(b.Id, reloaded.Index.Entries[0].Id); // newest first
        Assert.Equal(a.Id, reloaded.Index.Entries[1].Id);
    }

    [Fact]
    public void CapEvictionDeletesOwnedFiles()
    {
        var store = new HistoryStore(_dir, cap: 1);
        var first = store.AddScreenshot(Png(), 1)!;
        var firstImage = store.ImagePath(first)!;
        var firstThumb = store.ThumbPath(first);
        store.AddScreenshot(Png(), 1);
        Assert.Single(store.Index.Entries);
        Assert.False(File.Exists(firstImage));
        Assert.False(File.Exists(firstThumb));
    }

    [Fact]
    public void RemoveNeverDeletesSavedRecordingFile()
    {
        var store = new HistoryStore(_dir, 50);
        var rec = DummyRecording();
        var entry = store.AddRecording(rec, Png(), 50)!;
        var thumb = store.ThumbPath(entry);
        store.Remove(entry.Id);
        Assert.False(File.Exists(thumb));
        Assert.True(File.Exists(rec));
    }

    [Fact]
    public void ClearAllEmptiesIndexAndDeletesOwnedFiles()
    {
        var store = new HistoryStore(_dir, 50);
        var a = store.AddScreenshot(Png(), 50)!;
        store.AddScreenshot(Png(), 50);
        store.ClearAll();
        Assert.Empty(store.Index.Entries);
        Assert.False(File.Exists(store.ImagePath(a)!));
        Assert.Empty(new HistoryStore(_dir, 50).Index.Entries);
    }

    [Fact]
    public void CorruptIndexStartsEmpty()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "history.json"), "{ not valid json ]");
        Assert.Empty(new HistoryStore(_dir, 50).Index.Entries);
    }

    [Fact]
    public void AgePruneAppliesAtLoad()
    {
        var old = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var store = new HistoryStore(_dir, 50, now: old);
        store.AddScreenshot(Png(), 50, date: old, now: old);
        var reloaded = new HistoryStore(_dir, 50, now: old.AddDays(45));
        Assert.Empty(reloaded.Index.Entries);
    }

    [Fact]
    public void MissingRecordingFilePrunedAtLoad()
    {
        var store = new HistoryStore(_dir, 50);
        var rec = DummyRecording();
        store.AddRecording(rec, Png(), 50);
        File.Delete(rec);
        Assert.Empty(new HistoryStore(_dir, 50).Index.Entries);
    }

    [Fact]
    public void SavedFileExistsReflectsDisk()
    {
        var store = new HistoryStore(_dir, 50);
        var rec = DummyRecording();
        var entry = store.AddRecording(rec, Png(), 50)!;
        Assert.True(store.SavedFileExists(entry));
        File.Delete(rec);
        Assert.False(store.SavedFileExists(entry));
    }
}
