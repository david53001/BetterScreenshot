namespace BetterScreenshot.App.Overlays;

public enum QuickAccessKind { Screenshot, Recording }

/// <summary>Why a Quick Access card went away (Closed/Evicted are restorable; ActionTaken is not).</summary>
public enum DismissReason { Closed, Evicted, ActionTaken }

/// <summary>Callbacks the Quick Access card invokes for each action button.</summary>
public sealed class QuickAccessActions
{
    public Action OnCopy { get; init; } = () => { };
    public Action OnSave { get; init; } = () => { };
    public Action OnEdit { get; init; } = () => { };
    public Action OnPin { get; init; } = () => { };
    public Action OnOpen { get; init; } = () => { };
    public Action OnReveal { get; init; } = () => { };
}

/// <summary>A hand-authored icon path (24×24 viewbox). <see cref="Filled"/> = fill vs stroke.</summary>
public sealed record CardGlyph(string Data, bool Filled);

/// <summary>Original vector glyphs for the Quick Access buttons (refined into the full set in Phase 8).</summary>
public static class CardGlyphs
{
    public static readonly CardGlyph Copy = new("M8,8 h9 v9 h-9 z M5,5 h9 v9 h-9 z", false);
    public static readonly CardGlyph Save = new("M12,4 v9 M8,10 l4,4 l4,-4 M5,17 h14", false);
    public static readonly CardGlyph Edit = new("M6,18 l1,-4 l9,-9 l3,3 l-9,9 z", false);
    public static readonly CardGlyph Pin = new("M12,3 v7 M8,10 h8 l-2,4 h-4 z M12,14 v6", false);
    public static readonly CardGlyph Close = new("M7,7 l10,10 M17,7 l-10,10", false);
    public static readonly CardGlyph Play = new("M8,6 l10,6 l-10,6 z", true);
    public static readonly CardGlyph Folder = new("M4,7 h5 l2,2 h9 v9 h-16 z", false);
}
