using System.Diagnostics;
using System.IO;
using System.Linq;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Drives ffmpeg (via <see cref="FfmpegRunner"/>) to record a desktop region to an MP4, with gapless pause/resume
/// implemented as <b>segment-per-active-span + concat</b>: each active span is its own contiguous ffmpeg segment;
/// pausing finalizes the current segment, resuming starts a new one, and stopping concatenates them (<c>-c copy</c>,
/// all segments share identical encode settings) into the final MP4. Paused time is simply never captured, so the
/// output timeline is contiguous (the reference-sanctioned ffmpeg approach; the pure <see cref="PauseTimeline"/>
/// models the alternative PTS-retime strategy and is not needed here). One segment → just moved into place.
/// Pipes are drained in the background so a long segment never blocks on a full buffer.
/// </summary>
public sealed class RecordingEngine
{
    private readonly List<string> _segments = new();
    private Process? _process;
    private Task<string>? _stderr;
    private Task<string>? _stdout;

    private RecordingConfig _config = RecordingConfig.Default;
    private PxRect _region;
    private AudioInputs _audio = AudioInputs.None;
    private string? _finalPath;
    private string _sessionId = "";

    /// <summary>True while a recording session exists (recording or paused), from <see cref="Start"/> to <see cref="StopAsync"/>.</summary>
    public bool IsRecording => _finalPath is not null;

    /// <summary>ffmpeg's captured stderr from the most recent finished segment (diagnostics).</summary>
    public string LastStdErr { get; private set; } = "";

    /// <summary>Begin a recording session for <paramref name="region"/> → <paramref name="outputPath"/> (MP4). False if already active or ffmpeg is missing.</summary>
    public bool Start(RecordingConfig config, PxRect region, string outputPath, AudioInputs? audio = null)
    {
        if (_finalPath is not null) return false;
        if (!FfmpegRunner.IsAvailable()) return false;

        _config = config;
        _region = region;
        _audio = audio ?? AudioInputs.None;
        _finalPath = outputPath;
        _sessionId = Guid.NewGuid().ToString("N");
        _segments.Clear();
        StartSegment();
        return true;
    }

    /// <summary>Pause: finalize the current active-span segment (kept for concat); no frames are captured until <see cref="Resume"/>.</summary>
    public async Task PauseAsync()
    {
        if (_process is not null)
            await StopSegmentAsync();
    }

    /// <summary>Resume: begin a fresh segment with the same config/region/audio.</summary>
    public void Resume()
    {
        if (_finalPath is not null && _process is null)
            StartSegment();
    }

    /// <summary>Stop the session, concatenate the active-span segments into the final MP4, and return its path (or null).</summary>
    public async Task<string?> StopAsync()
    {
        if (_finalPath is null) return null;
        string final = _finalPath;
        _finalPath = null;

        await StopSegmentAsync();

        var segments = _segments.Where(s => File.Exists(s) && new FileInfo(s).Length > 0).ToList();
        _segments.Clear();
        if (segments.Count == 0) return null;

        try
        {
            if (segments.Count == 1)
            {
                if (File.Exists(final)) File.Delete(final);
                File.Move(segments[0], final);
            }
            else
            {
                await ConcatAsync(segments, final);
                foreach (var s in segments) TryDelete(s);
            }
        }
        catch
        {
            return null;
        }
        return File.Exists(final) ? final : null;
    }

    private void StartSegment()
    {
        string seg = Path.Combine(Path.GetTempPath(), $"bs_rec_{_sessionId}_{_segments.Count}.mp4");
        _segments.Add(seg);
        var args = FfmpegArgs.BuildRecording(_config, _region, seg, _audio);
        var process = FfmpegRunner.StartRecording(args);
        _stderr = process.StandardError.ReadToEndAsync();
        _stdout = process.StandardOutput.ReadToEndAsync();
        _process = process;
    }

    private async Task StopSegmentAsync()
    {
        var process = _process;
        _process = null;
        if (process is null) return;

        await FfmpegRunner.StopRecordingAsync(process);
        try { if (_stderr is not null) LastStdErr = await _stderr; } catch { /* pipe closed */ }
        try { if (_stdout is not null) await _stdout; } catch { /* pipe closed */ }
        _stderr = null;
        _stdout = null;
        process.Dispose();
    }

    private static async Task ConcatAsync(IReadOnlyList<string> segments, string output)
    {
        string list = Path.Combine(Path.GetTempPath(), $"bs_concat_{Guid.NewGuid():N}.txt");
        await File.WriteAllLinesAsync(list, segments.Select(s => $"file '{s.Replace("'", "'\\''")}'"));
        try
        {
            var (ok, err) = await FfmpegRunner.RunAsync(new[]
            {
                "-hide_banner", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", output,
            });
            if (!ok) throw new IOException("ffmpeg concat failed: " + err);
        }
        finally
        {
            TryDelete(list);
        }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
    }
}
