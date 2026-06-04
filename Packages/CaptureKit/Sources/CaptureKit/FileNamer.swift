import Foundation

public enum FileNamer {
    public static func fileName(for date: Date, ext: String, prefix: String = "Screenshot",
                                timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(f.string(from: date)).\(ext)"
    }
}
