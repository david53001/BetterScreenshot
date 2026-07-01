namespace BetterScreenshot.Capture;

public enum RecognitionKind
{
    None,
    Qr,
    Text,
}

/// <summary>Result of a Capture-Text run: a decoded QR payload, recognized text, or nothing.</summary>
public readonly struct RecognitionResult : IEquatable<RecognitionResult>
{
    public RecognitionKind Kind { get; }
    public string Value { get; }

    private RecognitionResult(RecognitionKind kind, string value)
    {
        Kind = kind;
        Value = value;
    }

    public static readonly RecognitionResult None = new(RecognitionKind.None, string.Empty);
    public static RecognitionResult Qr(string payload) => new(RecognitionKind.Qr, payload);
    public static RecognitionResult Text(string text) => new(RecognitionKind.Text, text);

    public string? ClipboardString => Kind == RecognitionKind.None ? null : Value;

    public string HudMessage => Kind switch
    {
        RecognitionKind.Qr => "QR code copied",
        RecognitionKind.Text => $"Text copied — {Value.Length} characters",
        _ => "No text found",
    };

    public bool Equals(RecognitionResult other) => Kind == other.Kind && Value == other.Value;
    public override bool Equals(object? obj) => obj is RecognitionResult r && Equals(r);
    public override int GetHashCode() => HashCode.Combine(Kind, Value);
    public static bool operator ==(RecognitionResult a, RecognitionResult b) => a.Equals(b);
    public static bool operator !=(RecognitionResult a, RecognitionResult b) => !a.Equals(b);
}

/// <summary>
/// Pure decision rule for Capture Text: a QR code (if any) wins over text; otherwise blank lines are dropped
/// and the remaining lines are joined with newlines; if nothing remains, the result is <see cref="RecognitionResult.None"/>.
/// </summary>
public static class RecognitionResolver
{
    public static RecognitionResult Resolve(IReadOnlyList<string> qrPayloads, IReadOnlyList<string> textLines)
    {
        foreach (var qr in qrPayloads)
        {
            if (!string.IsNullOrEmpty(qr)) return RecognitionResult.Qr(qr);
        }

        var kept = new List<string>();
        foreach (var line in textLines)
        {
            if (!string.IsNullOrEmpty(line)) kept.Add(line);
        }

        return kept.Count == 0 ? RecognitionResult.None : RecognitionResult.Text(string.Join("\n", kept));
    }
}
