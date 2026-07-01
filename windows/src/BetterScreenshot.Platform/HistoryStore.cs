using System.IO;
using BetterScreenshot.History;

namespace BetterScreenshot.Platform;

/// <summary>
/// File-backed capture history: a JSON index plus history-owned screenshot copies + JPEG thumbnails under a
/// directory. Applies retention (count cap, 30-day age, missing-file prune) at load. Recordings are stored by
/// reference — their saved file is never deleted by history. Corrupt index → start empty (never throws).
/// </summary>
public sealed class HistoryStore
{
    private readonly string _dir;

    public HistoryIndex Index { get; private set; }

    public HistoryStore(string directory, int cap, DateTime? now = null)
    {
        _dir = directory;
        Directory.CreateDirectory(_dir);
        Index = LoadAndPrune(cap, now ?? DateTime.UtcNow);
    }

    private string IndexPath => Path.Combine(_dir, "history.json");

    private HistoryIndex LoadAndPrune(int cap, DateTime now)
    {
        HistoryIndex loaded;
        try
        {
            loaded = File.Exists(IndexPath) ? HistoryIndex.FromJson(File.ReadAllText(IndexPath)) : new HistoryIndex();
        }
        catch
        {
            loaded = new HistoryIndex();
        }

        var (aged, evicted) = loaded.Pruned(cap, now);
        var (kept, missing) = aged.PrunedOfMissingFiles(FileExists);
        foreach (var e in evicted) DeleteOwnedFiles(e);
        foreach (var e in missing) DeleteOwnedFiles(e);
        Persist(kept);
        return kept;
    }

    private bool FileExists(HistoryEntry e) => e.Kind == HistoryKind.Screenshot
        ? e.ImageFile != null && File.Exists(Path.Combine(_dir, e.ImageFile))
        : e.FilePath != null && File.Exists(e.FilePath);

    public HistoryEntry? AddScreenshot(byte[] pngData, int cap, DateTime? date = null, DateTime? now = null)
    {
        var when = date ?? DateTime.UtcNow;
        var thumb = ThumbnailRenderer.JpegThumbnail(pngData);
        if (thumb is null) return null;

        var id = Guid.NewGuid();
        string imageFile = id.ToString("N") + ".png";
        string thumbFile = id.ToString("N") + "-thumb.jpg";
        try
        {
            File.WriteAllBytes(Path.Combine(_dir, imageFile), pngData);
            File.WriteAllBytes(Path.Combine(_dir, thumbFile), thumb);
        }
        catch
        {
            TryDelete(imageFile);
            TryDelete(thumbFile);
            return null;
        }

        var entry = new HistoryEntry { Id = id, Kind = HistoryKind.Screenshot, Date = when, ImageFile = imageFile, ThumbFile = thumbFile };
        Commit(entry, cap, now ?? when);
        return entry;
    }

    public HistoryEntry? AddRecording(string filePath, byte[] thumbnailSource, int cap, DateTime? date = null, DateTime? now = null)
    {
        var when = date ?? DateTime.UtcNow;
        var thumb = ThumbnailRenderer.JpegThumbnail(thumbnailSource);
        if (thumb is null) return null;

        var id = Guid.NewGuid();
        string thumbFile = id.ToString("N") + "-thumb.jpg";
        try
        {
            File.WriteAllBytes(Path.Combine(_dir, thumbFile), thumb);
        }
        catch
        {
            return null;
        }

        var entry = new HistoryEntry { Id = id, Kind = HistoryKind.Recording, Date = when, FilePath = filePath, ThumbFile = thumbFile };
        Commit(entry, cap, now ?? when);
        return entry;
    }

    private void Commit(HistoryEntry entry, int cap, DateTime now)
    {
        var (index, evicted) = Index.Adding(entry, cap, now);
        Index = index;
        foreach (var e in evicted) DeleteOwnedFiles(e);
        Persist(Index);
    }

    public HistoryEntry? Entry(Guid id) => Index.Entries.FirstOrDefault(e => e.Id == id);
    public string ThumbPath(HistoryEntry e) => Path.Combine(_dir, e.ThumbFile);
    public string? ImagePath(HistoryEntry e) => e.ImageFile is null ? null : Path.Combine(_dir, e.ImageFile);
    public string? SavedFilePath(HistoryEntry e) => e.FilePath;
    public bool SavedFileExists(HistoryEntry e) => e.FilePath != null && File.Exists(e.FilePath);

    public void Remove(Guid id)
    {
        var (index, removed) = Index.Removing(id);
        Index = index;
        if (removed != null) DeleteOwnedFiles(removed);
        Persist(Index);
    }

    public void ClearAll()
    {
        foreach (var e in Index.Entries) DeleteOwnedFiles(e);
        Index = new HistoryIndex();
        Persist(Index);
    }

    private void DeleteOwnedFiles(HistoryEntry e)
    {
        if (e.ImageFile != null) TryDelete(e.ImageFile);
        TryDelete(e.ThumbFile);
        // Never delete e.FilePath — that is the user's saved recording.
    }

    private void TryDelete(string fileName)
    {
        try
        {
            var path = Path.Combine(_dir, fileName);
            if (File.Exists(path)) File.Delete(path);
        }
        catch
        {
            // best effort
        }
    }

    private void Persist(HistoryIndex index)
    {
        try
        {
            File.WriteAllText(IndexPath, index.ToJson());
        }
        catch
        {
            // best effort; index stays in memory
        }
    }
}
