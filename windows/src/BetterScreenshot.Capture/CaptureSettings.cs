using System.Globalization;

namespace BetterScreenshot.Capture;

public enum AfterCaptureBehavior { CopyOnly, SaveOnly, CopyAndSave, ShowOverlay }
public enum SettingsImageFormat { Png, Jpg }
public enum SettingsOverlayCorner { TopLeft, TopRight, BottomLeft, BottomRight }

/// <summary>
/// Capture behavior settings, persisted as a flat string dictionary (1:1 with the macOS app's persisted keys).
/// Defaults: show the quick-access overlay, PNG, bottom-right corner, 30s auto-dismiss, pin radius 8 + shadow,
/// history enabled with a 50-item cap.
/// </summary>
public sealed record CaptureSettings
{
    public AfterCaptureBehavior AfterCapture { get; init; } = AfterCaptureBehavior.ShowOverlay;
    public SettingsImageFormat Format { get; init; } = SettingsImageFormat.Png;
    public SettingsOverlayCorner OverlayCorner { get; init; } = SettingsOverlayCorner.BottomRight;
    public int OverlayAutoDismissSeconds { get; init; } = 30;
    public int PinCornerRadius { get; init; } = 8;
    public bool PinShadow { get; init; } = true;
    public bool HistoryEnabled { get; init; } = true;
    public int HistoryCap { get; init; } = 50;

    public static CaptureSettings Default => new();

    public Dictionary<string, string> ToDictionary() => new()
    {
        ["afterCapture"] = AfterCapture switch
        {
            AfterCaptureBehavior.CopyOnly => "copyOnly",
            AfterCaptureBehavior.SaveOnly => "saveOnly",
            AfterCaptureBehavior.CopyAndSave => "copyAndSave",
            _ => "showOverlay",
        },
        ["format"] = Format == SettingsImageFormat.Jpg ? "jpg" : "png",
        ["overlayCorner"] = OverlayCorner switch
        {
            SettingsOverlayCorner.TopLeft => "topLeft",
            SettingsOverlayCorner.TopRight => "topRight",
            SettingsOverlayCorner.BottomLeft => "bottomLeft",
            _ => "bottomRight",
        },
        ["overlayAutoDismissSeconds"] = OverlayAutoDismissSeconds.ToString(CultureInfo.InvariantCulture),
        ["pinCornerRadius"] = PinCornerRadius.ToString(CultureInfo.InvariantCulture),
        ["pinShadow"] = PinShadow ? "true" : "false",
        ["historyEnabled"] = HistoryEnabled ? "true" : "false",
        ["historyCap"] = HistoryCap.ToString(CultureInfo.InvariantCulture),
    };

    public static CaptureSettings FromDictionary(IReadOnlyDictionary<string, string> d)
    {
        var def = Default;
        return new CaptureSettings
        {
            AfterCapture = d.TryGetValue("afterCapture", out var ac)
                ? ac switch
                {
                    "copyOnly" => AfterCaptureBehavior.CopyOnly,
                    "saveOnly" => AfterCaptureBehavior.SaveOnly,
                    "copyAndSave" => AfterCaptureBehavior.CopyAndSave,
                    "showOverlay" => AfterCaptureBehavior.ShowOverlay,
                    _ => def.AfterCapture,
                }
                : def.AfterCapture,
            Format = d.TryGetValue("format", out var f) ? (f == "jpg" ? SettingsImageFormat.Jpg : SettingsImageFormat.Png) : def.Format,
            OverlayCorner = d.TryGetValue("overlayCorner", out var oc)
                ? oc switch
                {
                    "topLeft" => SettingsOverlayCorner.TopLeft,
                    "topRight" => SettingsOverlayCorner.TopRight,
                    "bottomLeft" => SettingsOverlayCorner.BottomLeft,
                    "bottomRight" => SettingsOverlayCorner.BottomRight,
                    _ => def.OverlayCorner,
                }
                : def.OverlayCorner,
            // Snap to the slider's stop table so a legacy persisted value (e.g. an older build's 6s
            // default) resolves to a stop the Settings slider can show.
            OverlayAutoDismissSeconds = OverlayDismissScale.Snap(
                ParseInt(d, "overlayAutoDismissSeconds", def.OverlayAutoDismissSeconds)),
            PinCornerRadius = ParseInt(d, "pinCornerRadius", def.PinCornerRadius),
            PinShadow = ParseBool(d, "pinShadow", def.PinShadow),
            HistoryEnabled = ParseBool(d, "historyEnabled", def.HistoryEnabled),
            HistoryCap = ParseInt(d, "historyCap", def.HistoryCap),
        };
    }

    private static int ParseInt(IReadOnlyDictionary<string, string> d, string key, int fallback) =>
        d.TryGetValue(key, out var v) && int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : fallback;

    private static bool ParseBool(IReadOnlyDictionary<string, string> d, string key, bool fallback) =>
        d.TryGetValue(key, out var v) ? v == "true" : fallback;
}
