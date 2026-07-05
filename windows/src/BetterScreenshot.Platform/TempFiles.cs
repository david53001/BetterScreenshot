using System.IO;

namespace BetterScreenshot.Platform;

/// <summary>
/// Best-effort lifetime management for the temp PNGs that back clipboard/drag-export payloads. Each such file
/// lives in its own unique <c>%TEMP%\BetterScreenshot-{guid}\</c> subdirectory (see <see cref="ImageIo.WriteTempPng"/>),
/// completely separate from capture history (<c>%APPDATA%\BetterScreenshot\History\</c>) — so auto-deleting one of
/// these temp files never removes the capture itself, which history keeps as its own copy.
/// </summary>
public static class TempFiles
{
    /// <summary>How long a drag/clipboard temp PNG is kept alive before it is auto-deleted. Long enough that an
    /// app receiving a drop can still read the file, short enough that temp does not accumulate images.</summary>
    public static readonly TimeSpan PayloadLifetime = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Deletes the unique temp subdirectory that contains <paramref name="filePath"/> after <paramref name="delay"/>.
    /// Best-effort: a null/empty path is a no-op, and a locked/already-gone directory is ignored. Because each
    /// payload PNG owns its own guid subdirectory, deleting the containing directory removes only that one file.
    /// </summary>
    public static void ScheduleDeleteContainingDir(string? filePath, TimeSpan delay)
    {
        if (string.IsNullOrEmpty(filePath)) return;
        var dir = Path.GetDirectoryName(filePath);
        if (string.IsNullOrEmpty(dir)) return;

        _ = Task.Delay(delay).ContinueWith(_ =>
        {
            try
            {
                if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
            }
            catch
            {
                // Best-effort cleanup; ignore if the file is locked or already gone.
            }
        });
    }
}
