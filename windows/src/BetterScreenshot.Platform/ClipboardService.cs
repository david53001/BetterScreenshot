using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace BetterScreenshot.Platform;

/// <summary>
/// Clipboard interactions. <see cref="SetImage"/> puts both the bitmap and a file-drop of a temp PNG on the
/// clipboard (so it can be pasted as an image or dropped as a file), then deletes the temp file after 5 minutes.
/// Must be called on an STA thread (the WPF UI thread at runtime).
/// </summary>
public static class ClipboardService
{
    private static readonly TimeSpan TempLifetime = TimeSpan.FromMinutes(5);

    public static void SetImage(BitmapSource image)
    {
        string tempPng = ImageIo.WriteTempPng(image, "clipboard.png");
        var data = new DataObject();
        data.SetImage(image);
        data.SetFileDropList(new StringCollection { tempPng });
        Clipboard.SetDataObject(data, copy: true);
        ScheduleDelete(Path.GetDirectoryName(tempPng));
    }

    public static void SetText(string text) => Clipboard.SetText(text);

    /// <summary>Puts a single existing file on the clipboard as a file-drop (e.g. a saved recording).</summary>
    public static void SetFile(string path)
    {
        var data = new DataObject();
        data.SetFileDropList(new StringCollection { path });
        Clipboard.SetDataObject(data, copy: true);
    }

    private static void ScheduleDelete(string? dir)
    {
        if (string.IsNullOrEmpty(dir)) return;
        _ = Task.Delay(TempLifetime).ContinueWith(_ =>
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
