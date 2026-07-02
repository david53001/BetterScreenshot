using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Orchestrates screen recording: owns the <see cref="RecorderState"/> machine and the ffmpeg
/// <see cref="RecordingEngine"/>, picks the capture region, resolves audio devices, drives a 1s tray timer, and on
/// stop hands the finished MP4 + a thumbnail back to the app for the history record and Quick Access card.
///
/// This is the start/stop core wired to <c>ToggleRecording</c>. It records the full primary display for now; area/
/// window targets and the record-strip picker UI, plus gapless pause/resume (Task 7.3), build on top of this.
/// The whole start/stop flow stays on the UI thread (no ConfigureAwait(false) here) so the DispatcherTimer and the
/// state-change callback run on the dispatcher.
/// </summary>
public sealed class RecordingCoordinator
{
    private readonly SettingsStore _settings;
    private readonly RecordingEngine _engine = new();
    private readonly DispatcherTimer _timer;
    private readonly Action<bool, string?> _onStateChange;
    private readonly Action<string, BitmapSource> _onFinished;

    private RecorderState _state = RecorderState.Idle;
    private bool _busy; // guards against overlapping start/stop while an async transition is in flight

    public RecordingCoordinator(SettingsStore settings, Action<bool, string?> onStateChange,
        Action<string, BitmapSource> onFinished)
    {
        _settings = settings;
        _onStateChange = onStateChange;
        _onFinished = onFinished;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => _onStateChange(true, _state.ElapsedString(DateTime.Now));
    }

    public bool IsRecording => _state.Phase is RecorderPhase.Recording or RecorderPhase.Paused;

    /// <summary>Start recording (full screen) if idle, else stop. Fire-and-forget from the hotkey / tray menu.</summary>
    public void Toggle() => _ = ToggleAsync();

    private async Task ToggleAsync()
    {
        if (_busy) return;
        _busy = true;
        try
        {
            if (IsRecording) await StopAsync();
            else await StartFullScreenAsync();
        }
        finally
        {
            _busy = false;
        }
    }

    private async Task StartFullScreenAsync()
    {
        if (!FfmpegRunner.IsAvailable())
        {
            HudController.Show("ffmpeg not found — recording unavailable");
            return;
        }

        var monitor = Screens.Primary();
        var region = monitor.Bounds;
        var config = _settings.Recording;

        Directory.CreateDirectory(_settings.RecordingsDirectory);
        string path = Path.Combine(_settings.RecordingsDirectory, FileNamer.Name(DateTime.Now, "mp4", "Recording"));

        // Resolve audio devices off the UI thread; the await resumes back on the dispatcher (no ConfigureAwait here).
        var audio = await DshowAudioDevices.ResolveAsync(config);

        if (!_state.Transition(RecorderEvent.Arm)) return;
        if (!_state.Transition(RecorderEvent.Begin, DateTime.Now)) { _state = RecorderState.Idle; return; }

        if (!_engine.Start(config, region, path, audio))
        {
            _state = RecorderState.Idle;
            HudController.Show("Could not start recording");
            return;
        }

        _timer.Start();
        _onStateChange(true, _state.ElapsedString(DateTime.Now));
    }

    private async Task StopAsync()
    {
        _timer.Stop();
        _state.Transition(RecorderEvent.Finish);

        // A representative still (the display as it is at stop ≈ the final frame) for the card + history thumbnail.
        var thumb = CaptureThumb();
        string? path = await _engine.StopAsync();

        _state = RecorderState.Idle;
        _onStateChange(false, null);

        if (path is not null)
            _onFinished(path, thumb);
    }

    private static BitmapSource CaptureThumb()
    {
        try
        {
            return ScreenCapture.CaptureDisplay(Screens.Primary());
        }
        catch
        {
            var blank = new WriteableBitmap(2, 2, 96, 96, PixelFormats.Bgra32, null);
            blank.Freeze();
            return blank;
        }
    }
}
