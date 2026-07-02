using System.Diagnostics;
using System.IO;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Drives ffmpeg (via <see cref="FfmpegRunner"/>) to record a desktop region to an MP4. Owns at most one ffmpeg
/// process at a time; <see cref="FfmpegArgs"/> builds the command line. The stderr/stdout pipes are drained in the
/// background so a long recording never blocks on a full pipe buffer. Gapless pause/resume (Task 7.3) and GIF
/// conversion (Task 7.5) build on top of this start/stop core; the <see cref="RecordingCoordinator"/> (Task 7.2)
/// will pick targets, resolve audio devices, and update the tray.
/// </summary>
public sealed class RecordingEngine
{
    private Process? _process;
    private string? _outputPath;
    private Task<string>? _stderr;
    private Task<string>? _stdout;

    /// <summary>True while an ffmpeg recording process is alive.</summary>
    public bool IsRecording => _process is { HasExited: false };

    /// <summary>ffmpeg's captured stderr from the most recent recording (diagnostics), populated after <see cref="StopAsync"/>.</summary>
    public string LastStdErr { get; private set; } = "";

    /// <summary>
    /// Starts recording <paramref name="region"/> (physical desktop pixels, top-left) to a fresh MP4 at
    /// <paramref name="outputPath"/>. Returns false if a recording is already running or ffmpeg is unavailable.
    /// </summary>
    public bool Start(RecordingConfig config, PxRect region, string outputPath, AudioInputs? audio = null)
    {
        if (IsRecording) return false;
        if (!FfmpegRunner.IsAvailable()) return false;

        var args = FfmpegArgs.BuildRecording(config, region, outputPath, audio ?? AudioInputs.None);
        var process = FfmpegRunner.StartRecording(args);
        // Drain both pipes so ffmpeg can't block on a full stderr/stdout buffer during a long recording.
        _stderr = process.StandardError.ReadToEndAsync();
        _stdout = process.StandardOutput.ReadToEndAsync();
        _process = process;
        _outputPath = outputPath;
        return true;
    }

    /// <summary>
    /// Stops the recording gracefully (ffmpeg finalizes the MP4 moov atom) and returns the finished file path,
    /// or null if nothing was recorded or the file is missing.
    /// </summary>
    public async Task<string?> StopAsync()
    {
        var process = _process;
        var path = _outputPath;
        if (process is null) return null;
        _process = null;
        _outputPath = null;

        await FfmpegRunner.StopRecordingAsync(process);
        try { if (_stderr is not null) LastStdErr = await _stderr; } catch { /* pipe closed */ }
        try { if (_stdout is not null) await _stdout; } catch { /* pipe closed */ }
        _stderr = null;
        _stdout = null;
        process.Dispose();

        return path is not null && File.Exists(path) ? path : null;
    }
}
