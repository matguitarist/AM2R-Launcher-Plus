import Foundation

/// Rules for profile names. Logic lives in this library so tests can run it
/// without the app. Patching, validation and config.ini rules go here too.
public enum ProfileName {
    /// Trims spaces and line breaks, collapses inner runs of spaces, and
    /// falls back to "Community Updates" for an empty name.
    public static func clean(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? "Community Updates" : words.joined(separator: " ")
    }

    /// "Community Updates 1.5.5 Copy", then "… Copy 2", "… Copy 3" when those are taken (S-022).
    public static func copy(of name: String, existing: [String]) -> String {
        let taken = Set(existing)
        let first = "\(name) Copy"
        if !taken.contains(first) { return first }
        var number = 2
        while taken.contains("\(first) \(number)") { number += 1 }
        return "\(first) \(number)"
    }

    /// Folder name for saves kept after deleting a profile: "Community Updates 1.5.5 – 2026-11-03 14-05".
    /// Slashes and colons, which Finder can't show, become dashes.
    public static func keptSavesFolder(for name: String, date: Date, timeZone: TimeZone = .current) -> String {
        dated(name, date: date, timeZone: timeZone)
    }

    /// "Community Updates 1.5.5 – 2026-11-03 14-05", safe as a file name (kept saves, backups).
    public static func dated(_ name: String, date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d-%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
        let safe = clean(name).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe) – \(stamp)"
    }
}
