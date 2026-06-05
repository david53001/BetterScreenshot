import Foundation

public enum HistoryKind: String, Codable, Equatable {
    case screenshot, recording
}

/// One remembered capture. Screenshots own a full-res PNG copy (`imageFile`);
/// recordings reference the user's saved file (`filePath`). Both own a JPEG
/// thumbnail. `imageFile`/`thumbFile` are names relative to the history
/// directory; `filePath` is absolute.
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: HistoryKind
    public let date: Date
    public let imageFile: String?
    public let filePath: String?
    public let thumbFile: String

    public init(id: UUID = UUID(), kind: HistoryKind, date: Date,
                imageFile: String? = nil, filePath: String? = nil, thumbFile: String) {
        self.id = id; self.kind = kind; self.date = date
        self.imageFile = imageFile; self.filePath = filePath; self.thumbFile = thumbFile
    }
}
