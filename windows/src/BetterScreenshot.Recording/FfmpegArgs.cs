using System.Globalization;
using BetterScreenshot.Core;

namespace BetterScreenshot.Recording;

/// <summary>
/// The resolved audio capture devices for a recording. The pure arg builder only formats these into ffmpeg
/// <c>dshow</c> inputs; discovering the actual device names (a loopback-capable device for system audio, the
/// default microphone) is the Platform/engine's job. A null device means "unavailable" — that track is dropped.
/// </summary>
public sealed record AudioInputs
{
    /// <summary>dshow device name that captures system-audio loopback (e.g. "Stereo Mix" or a virtual cable), or null.</summary>
    public string? SystemAudioDevice { get; init; }

    /// <summary>dshow device name for the microphone, or null.</summary>
    public string? MicrophoneDevice { get; init; }

    /// <summary>No audio devices available — records video only.</summary>
    public static AudioInputs None => new();
}

/// <summary>
/// Builds the ffmpeg command-line arguments for a Windows screen recording (pure — deterministic strings, unit
/// tested). Video is captured with <c>gdigrab</c> over a desktop-relative pixel region (a display, an area
/// selection, or a tracked window rect all reduce to one region). System audio and the microphone become separate
/// <c>dshow</c> AAC tracks, included only when the config requests them and a device name is supplied. The
/// recording pass always encodes H.264/MP4; a GIF request is a separate post-conversion pass (later task).
/// </summary>
public static class FfmpegArgs
{
    /// <summary>Args to record <paramref name="region"/> (physical desktop pixels, top-left) to <paramref name="outputPath"/> (MP4).</summary>
    public static IReadOnlyList<string> BuildRecording(
        RecordingConfig config, PxRect region, string outputPath, AudioInputs audio)
    {
        string fpsStr = config.Fps.ToString(CultureInfo.InvariantCulture);

        int offsetX = (int)Math.Round(region.X);
        int offsetY = (int)Math.Round(region.Y);
        // H.264 (yuv420p) needs even dimensions — floor width/height to even, and size the bitrate off the same dims.
        int width = EvenFloor(region.Width);
        int height = EvenFloor(region.Height);

        var args = new List<string> { "-hide_banner", "-y" };

        // Video input: gdigrab over the region (cursor drawn, per the mac recorder's showsCursor).
        args.AddRange(new[]
        {
            "-f", "gdigrab",
            "-framerate", fpsStr,
            "-draw_mouse", "1",
            "-offset_x", offsetX.ToString(CultureInfo.InvariantCulture),
            "-offset_y", offsetY.ToString(CultureInfo.InvariantCulture),
            "-video_size", $"{width}x{height}",
            "-i", "desktop",
        });

        // Audio inputs (system first, then mic) — only when requested AND a device is available.
        bool includeSystem = config.SystemAudio && audio.SystemAudioDevice is not null;
        bool includeMic = config.Microphone && audio.MicrophoneDevice is not null;
        if (includeSystem)
            args.AddRange(new[] { "-f", "dshow", "-i", $"audio={audio.SystemAudioDevice}" });
        if (includeMic)
            args.AddRange(new[] { "-f", "dshow", "-i", $"audio={audio.MicrophoneDevice}" });

        // Video encode (H.264, target bitrate from the pure config formula).
        long bitrate = config.VideoBitrate(width, height);
        args.AddRange(new[]
        {
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-b:v", bitrate.ToString(CultureInfo.InvariantCulture),
            "-r", fpsStr,
        });

        // Audio encode + explicit mapping (each audio input is its own 48kHz/2ch/128k AAC track, not pre-mixed).
        if (includeSystem || includeMic)
        {
            args.AddRange(new[] { "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2" });
            args.AddRange(new[] { "-map", "0:v" });
            int audioIndex = 1;
            if (includeSystem) { args.AddRange(new[] { "-map", $"{audioIndex}:a" }); audioIndex++; }
            if (includeMic) { args.AddRange(new[] { "-map", $"{audioIndex}:a" }); }
        }

        args.Add(outputPath);
        return args;
    }

    private static int EvenFloor(double v)
    {
        int n = (int)Math.Floor(v);
        return n - (n & 1);
    }
}
