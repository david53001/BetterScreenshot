using BetterScreenshot.Recording;

namespace BetterScreenshot.Platform;

/// <summary>
/// Discovers dshow capture devices by running <c>ffmpeg -list_devices</c> and parsing its stderr (via the pure
/// <see cref="DshowDeviceList"/>), then resolves the <see cref="AudioInputs"/> for a recording. The device list
/// is cached (it changes rarely and enumeration spawns an ffmpeg process); call <see cref="InvalidateCache"/>
/// after a known device change. Enumeration is best-effort — any failure yields "no devices", so recording simply
/// falls back to video-only.
/// </summary>
public static class DshowAudioDevices
{
    private static Task<DshowDeviceSet>? _cached;

    /// <summary>Enumerate (and cache) the dshow devices. Never throws — returns empty sets on failure.</summary>
    public static Task<DshowDeviceSet> EnumerateAsync() => _cached ??= EnumerateCoreAsync();

    private static async Task<DshowDeviceSet> EnumerateCoreAsync()
    {
        try
        {
            // -list_devices exits non-zero ("Error opening input file dummy") but still prints the list to stderr.
            var (_, stderr) = await FfmpegRunner
                .RunAsync(new[] { "-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy" }, 8000)
                .ConfigureAwait(false);
            return DshowDeviceList.Parse(stderr);
        }
        catch
        {
            return new DshowDeviceSet(Array.Empty<string>(), Array.Empty<string>());
        }
    }

    /// <summary>Resolve which loopback/mic devices to feed ffmpeg for <paramref name="config"/> (each may be null → dropped).</summary>
    public static async Task<AudioInputs> ResolveAsync(RecordingConfig config)
    {
        var set = await EnumerateAsync().ConfigureAwait(false);
        string? system = config.SystemAudio ? DshowDeviceList.PickSystemLoopback(set.Audio) : null;
        string? mic = config.Microphone ? DshowDeviceList.PickMicrophone(set.Audio, excluding: system) : null;
        return new AudioInputs { SystemAudioDevice = system, MicrophoneDevice = mic };
    }

    /// <summary>Drops the cached device list so the next resolve re-enumerates.</summary>
    public static void InvalidateCache() => _cached = null;
}
