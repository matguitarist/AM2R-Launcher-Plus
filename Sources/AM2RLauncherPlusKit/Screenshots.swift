import Foundation

/// Screenshots the game saves with F12 (S-041): AM2R writes snap/snap NNNN.png in its save folder
/// (oControl KeyPress F12, screen_save, engine patch 0013).
public enum Screenshots {
    public static func folder(in saves: URL) -> URL { saves.appending(path: "snap", directoryHint: .isDirectory) }

    /// The PNGs in the snap folder, newest first (by date, then by name for equal dates).
    public static func list(in saves: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(in: saves), includingPropertiesForKeys: Array(keys))) ?? []
        var dated: [(url: URL, date: Date)] = []
        for file in files where file.pathExtension.lowercased() == "png" {
            let date = (try? file.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            dated.append((file, date))
        }
        dated.sort { a, b in a.date != b.date ? a.date > b.date : a.url.lastPathComponent > b.url.lastPathComponent }
        return dated.map(\.url)
    }
}
