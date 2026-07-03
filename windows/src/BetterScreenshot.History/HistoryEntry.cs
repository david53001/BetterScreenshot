namespace BetterScreenshot.History;

public enum HistoryKind { Screenshot, Recording }

/// <summary>
/// One remembered capture. Screenshots are owned by history (a copied PNG + thumbnail); recordings are stored
/// by reference (the user's saved file path is never deleted by history). A thumbnail is always present.
/// </summary>
public sealed record HistoryEntry
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public HistoryKind Kind { get; init; }
    public DateTime Date { get; init; }

    /// <summary>History-owned PNG filename (screenshots only).</summary>
    public string? ImageFile { get; init; }

    /// <summary>Absolute path to the user's saved recording (recordings only). Never deleted by history.</summary>
    public string? FilePath { get; init; }

    /// <summary>History-owned JPEG thumbnail filename. Always present.</summary>
    public string ThumbFile { get; init; } = string.Empty;
}
