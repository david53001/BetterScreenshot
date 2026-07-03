using System.IO;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>Converts a recorded MP4 to a looping GIF via ffmpeg (args from <see cref="FfmpegArgs.BuildGifConversion"/>).</summary>
public static class GifExporter
{
    /// <summary>Returns the .gif path on success (the source MP4 is deleted), or null on failure (the MP4 is kept so nothing is lost).</summary>
    public static async Task<string?> ConvertAsync(string mp4Path, string gifPath)
    {
        var args = FfmpegArgs.BuildGifConversion(mp4Path, gifPath);
        var (ok, _) = await FfmpegRunner.RunAsync(args);
        if (ok && File.Exists(gifPath))
        {
            try { File.Delete(mp4Path); } catch { /* leave the mp4 if it can't be removed */ }
            return gifPath;
        }
        return null;
    }
}
