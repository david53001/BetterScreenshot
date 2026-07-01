using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
// Disambiguate WPF types from the WinForms types the App project also references (for the tray NotifyIcon).
using Button = System.Windows.Controls.Button;
using FontFamily = System.Windows.Media.FontFamily;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;
using Orientation = System.Windows.Controls.Orientation;

namespace BetterScreenshot.App.Settings;

/// <summary>Tabbed settings (General / Shortcuts / Recording). Persists to <see cref="SettingsStore"/> on Save;
/// the shortcut recorder rebinds hotkeys live via the <see cref="HotkeyController"/> (reverted on Cancel).</summary>
public partial class SettingsWindow : Window
{
    private static readonly int[] PinRadii = { 0, 4, 8, 12, 16, 20 };
    private static readonly int[] HistoryCaps = { 10, 50, 200 };

    private readonly SettingsStore _settings;
    private readonly HotkeyController _hotkeys;
    private readonly Dictionary<string, string> _hotkeySnapshot;
    private readonly Dictionary<HotkeyAction, TextBlock> _shortcutLabels = new();

    private HotkeyAction? _recordingAction;
    private Button? _recordingButton;
    private bool _saved;

    public SettingsWindow(SettingsStore settings, HotkeyController hotkeys)
    {
        _settings = settings;
        _hotkeys = hotkeys;
        _hotkeySnapshot = settings.Hotkeys.ToDictionary();
        InitializeComponent();
        LoadGeneral();
        LoadRecording();
        BuildShortcutRows();
    }

    private void LoadGeneral()
    {
        var c = _settings.Capture;
        AfterCaptureCombo.SelectedIndex = c.AfterCapture switch
        {
            AfterCaptureBehavior.CopyOnly => 1,
            AfterCaptureBehavior.SaveOnly => 2,
            AfterCaptureBehavior.CopyAndSave => 3,
            _ => 0,
        };
        FormatCombo.SelectedIndex = c.Format == SettingsImageFormat.Jpg ? 1 : 0;
        CornerCombo.SelectedIndex = c.OverlayCorner switch
        {
            SettingsOverlayCorner.TopLeft => 0,
            SettingsOverlayCorner.TopRight => 1,
            SettingsOverlayCorner.BottomLeft => 2,
            _ => 3,
        };
        AutoDismissCombo.SelectedIndex = c.OverlayAutoDismissSeconds switch { 3 => 0, 10 => 2, _ => 1 };
        SaveDirBox.Text = _settings.SaveDirectory;
        PinRadiusCombo.SelectedIndex = Math.Max(0, Array.IndexOf(PinRadii, c.PinCornerRadius));
        PinShadowCheck.IsChecked = c.PinShadow;
        HistoryEnabledCheck.IsChecked = c.HistoryEnabled;
        HistoryCapCombo.SelectedIndex = Math.Max(0, Array.IndexOf(HistoryCaps, c.HistoryCap));
        LaunchAtLoginCheck.IsChecked = _settings.LaunchAtLogin;
        CaptureSoundCheck.IsChecked = _settings.CaptureSoundEnabled;
    }

    private void LoadRecording()
    {
        var r = _settings.Recording;
        RecFormatCombo.SelectedIndex = r.Format == RecordingFormat.Gif ? 1 : 0;
        FpsCombo.SelectedIndex = r.Fps == 60 ? 1 : 0;
        SysAudioCheck.IsChecked = r.SystemAudio;
        MicCheck.IsChecked = r.Microphone;
        CameraCheck.IsChecked = r.Camera;
        CameraSizeCombo.SelectedIndex = r.CameraSize == CameraSize.Medium ? 1 : 0;
        ClicksCheck.IsChecked = r.ClickHighlights;
        KeystrokesCheck.IsChecked = r.KeystrokeOverlay;
        CountdownCombo.SelectedIndex = r.CountdownSeconds switch { 3 => 1, 5 => 2, 10 => 3, _ => 0 };
    }

    private void BuildShortcutRows()
    {
        foreach (var action in HotkeyActionInfo.All)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 5) };
            row.Children.Add(new TextBlock { Text = action.Title(), Width = 190, VerticalAlignment = VerticalAlignment.Center });

            var label = new TextBlock
            {
                Text = _settings.Hotkeys.Combo(action)?.DisplayString ?? "(unbound)",
                Width = 130,
                VerticalAlignment = VerticalAlignment.Center,
                FontFamily = new FontFamily("Consolas"),
            };
            _shortcutLabels[action] = label;
            row.Children.Add(label);

            var change = new Button { Content = "Change", Padding = new Thickness(8, 2, 8, 2), Tag = action };
            change.Click += StartRecording;
            row.Children.Add(change);

            var clear = new Button { Content = "Clear", Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(6, 0, 0, 0), Tag = action };
            clear.Click += ClearBinding;
            row.Children.Add(clear);

            ShortcutsPanel.Children.Add(row);
        }
    }

    private void StartRecording(object sender, RoutedEventArgs e)
    {
        StopRecording(); // cancel any in-progress recording
        _recordingButton = (Button)sender;
        _recordingAction = (HotkeyAction)_recordingButton.Tag;
        _recordingButton.Content = "Press keys…";
        _hotkeys.Suspend(); // don't let global hotkeys fire while capturing a combo
    }

    private void ClearBinding(object sender, RoutedEventArgs e)
    {
        var action = (HotkeyAction)((Button)sender).Tag;
        _settings.Hotkeys.Clear(action);
        _shortcutLabels[action].Text = "(unbound)";
        _hotkeys.Apply(_settings.Hotkeys);
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (_recordingAction is not { } action)
        {
            base.OnPreviewKeyDown(e);
            return;
        }

        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape) { StopRecording(); return; }

        if (ShortcutRecorder.TryBuildCombo(key, Keyboard.Modifiers) is not { } combo) return;

        if (_settings.Hotkeys.ConflictingAction(combo, excluding: action) is { } other)
        {
            MessageBox.Show(this, $"{combo.DisplayString} is already used by \"{other.Title()}\".",
                "Shortcut in use", MessageBoxButton.OK, MessageBoxImage.Warning);
            StopRecording();
            return;
        }

        _settings.Hotkeys.Set(action, combo);
        _shortcutLabels[action].Text = combo.DisplayString;
        StopRecording();
    }

    private void StopRecording()
    {
        if (_recordingButton != null) _recordingButton.Content = "Change";
        _recordingButton = null;
        _recordingAction = null;
        _hotkeys.Apply(_settings.Hotkeys);
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = "Choose save folder" };
        if (!string.IsNullOrWhiteSpace(SaveDirBox.Text)) dialog.InitialDirectory = SaveDirBox.Text;
        if (dialog.ShowDialog(this) == true) SaveDirBox.Text = dialog.FolderName;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        _settings.Capture = new CaptureSettings
        {
            AfterCapture = AfterCaptureCombo.SelectedIndex switch
            {
                1 => AfterCaptureBehavior.CopyOnly,
                2 => AfterCaptureBehavior.SaveOnly,
                3 => AfterCaptureBehavior.CopyAndSave,
                _ => AfterCaptureBehavior.ShowOverlay,
            },
            Format = FormatCombo.SelectedIndex == 1 ? SettingsImageFormat.Jpg : SettingsImageFormat.Png,
            OverlayCorner = CornerCombo.SelectedIndex switch
            {
                0 => SettingsOverlayCorner.TopLeft,
                1 => SettingsOverlayCorner.TopRight,
                2 => SettingsOverlayCorner.BottomLeft,
                _ => SettingsOverlayCorner.BottomRight,
            },
            OverlayAutoDismissSeconds = AutoDismissCombo.SelectedIndex switch { 0 => 3, 2 => 10, _ => 6 },
            PinCornerRadius = PinRadii[Math.Max(0, PinRadiusCombo.SelectedIndex)],
            PinShadow = PinShadowCheck.IsChecked == true,
            HistoryEnabled = HistoryEnabledCheck.IsChecked == true,
            HistoryCap = HistoryCaps[Math.Max(0, HistoryCapCombo.SelectedIndex)],
        };

        _settings.Recording = new RecordingConfig
        {
            Format = RecFormatCombo.SelectedIndex == 1 ? RecordingFormat.Gif : RecordingFormat.Mp4,
            Fps = FpsCombo.SelectedIndex == 1 ? 60 : 30,
            SystemAudio = SysAudioCheck.IsChecked == true,
            Microphone = MicCheck.IsChecked == true,
            Camera = CameraCheck.IsChecked == true,
            CameraSize = CameraSizeCombo.SelectedIndex == 1 ? CameraSize.Medium : CameraSize.Small,
            ClickHighlights = ClicksCheck.IsChecked == true,
            KeystrokeOverlay = KeystrokesCheck.IsChecked == true,
            CountdownSeconds = CountdownCombo.SelectedIndex switch { 1 => 3, 2 => 5, 3 => 10, _ => 0 },
        };

        _settings.SaveDirectory = SaveDirBox.Text;
        _settings.LaunchAtLogin = LaunchAtLoginCheck.IsChecked == true;
        _settings.CaptureSoundEnabled = CaptureSoundCheck.IsChecked == true;
        _settings.Save();

        _saved = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosed(EventArgs e)
    {
        if (!_saved) _settings.Hotkeys = HotkeyBindings.FromDictionary(_hotkeySnapshot);
        _hotkeys.Apply(_settings.Hotkeys);
        base.OnClosed(e);
    }
}
