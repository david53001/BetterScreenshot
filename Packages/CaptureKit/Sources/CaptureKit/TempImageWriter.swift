import Foundation
import CoreGraphics

public enum TempImageWriter {
    /// Writes a PNG into a unique temp subdirectory and returns its URL (nil on failure).
    public static func writePNG(_ image: CGImage, fileName: String) -> URL? {
        guard let data = ImageEncoder.encode(image, as: .png) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterScreenshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url)
            return url
        } catch { return nil }
    }
}
