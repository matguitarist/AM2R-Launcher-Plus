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
}
