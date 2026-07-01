namespace BetterScreenshot.Capture;

/// <summary>Pure decision for what happens to a fresh capture, based on the after-capture setting.</summary>
public static class CaptureRouter
{
    public static (bool Copy, bool Save, bool Overlay) Decide(AfterCaptureBehavior behavior) => behavior switch
    {
        AfterCaptureBehavior.CopyOnly => (true, false, false),
        AfterCaptureBehavior.SaveOnly => (false, true, false),
        AfterCaptureBehavior.CopyAndSave => (true, true, false),
        AfterCaptureBehavior.ShowOverlay => (false, false, true),
        _ => (false, false, true),
    };
}
