using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// A window that can be picked for window-capture/recording. <see cref="Layer"/> 0 = a normal top-level window
/// (higher layers are menus/popups/overlays, which are skipped). <see cref="OwnerPid"/> lets us exclude our own app.
/// </summary>
public readonly record struct PickableWindow(uint Id, PxRect Frame, string? Title, int Layer, int OwnerPid);

/// <summary>Pure window hit-testing: pick the frontmost normal window under a point.</summary>
public static class WindowPicking
{
    /// <summary>
    /// Given windows in front-to-back order, returns the frontmost normal-layer (layer 0) window that contains
    /// <paramref name="point"/> and is not owned by <paramref name="excludePid"/>, or null if none match.
    /// </summary>
    public static PickableWindow? Topmost(PxPoint point, IReadOnlyList<PickableWindow> windows, int excludePid)
    {
        foreach (var w in windows)
        {
            if (w.Layer != 0) continue;
            if (w.OwnerPid == excludePid) continue;
            if (w.Frame.Contains(point)) return w;
        }
        return null;
    }
}
