namespace BetterScreenshot.App.Overlays;

/// <summary>Visual style for a pinned panel.</summary>
public sealed record PinStyle(double CornerRadius, bool Shadow);

/// <summary>Context-menu / double-click actions for a pinned panel.</summary>
public sealed record PinActions(Action OnCopy, Action OnSave);
