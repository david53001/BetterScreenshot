import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: Equatable {
    case png
    case jpg(quality: CGFloat)
}

public enum ImageEncoder {
    public static func encode(_ image: CGImage, as format: ImageFormat) -> Data? {
        let utType: UTType = {
            switch format { case .png: return .png; case .jpg: return .jpeg }
        }()
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, utType.identifier as CFString, 1, nil
        ) else { return nil }
        var options: [CFString: Any] = [:]
        if case let .jpg(quality) = format {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
