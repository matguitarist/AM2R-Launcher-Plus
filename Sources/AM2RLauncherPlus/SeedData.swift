import AM2RLauncherPlusKit
import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with profiles a person can get by installing from AM2R 1.1.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Profile>())) ?? 0) == 0 else { return }
        let older = Profile(name: "Community Updates 1.5.4", version: "1.5.4")
        older.engine = .rosetta
        older.installedAt = Date.now.addingTimeInterval(-90 * 86_400)
        older.playTime = 11 * 3_600
        older.lastPlayedAt = Date.now.addingTimeInterval(-30 * 86_400)
        context.insert(older)
        // S-033: a mod installed next to Community Updates.
        let mod = Profile(name: "Sample Mod 1.2", version: "1.2")
        mod.isMod = true
        mod.author = "A Modder"
        mod.installedAt = Date.now.addingTimeInterval(-7 * 86_400)
        mod.lastPlayedAt = Date.now.addingTimeInterval(-2 * 86_400)
        mod.playTime = 45 * 60
        mod.notes = "A sample mod with a longer description, the way mods describe themselves in their profile.xml, so the Mods page shows two lines of it."
        context.insert(mod)
        // The community mod list, offline.
        model.modCatalog = [
            ModCatalog.Entry(category: "Mods for Community Updates", name: "AM2R Turbo Edition", author: "DodoBirb",
                             summary: "A mod for AM2R 1.5.5 that adds several new speedbooster techniques.", link: URL(string: "https://example.com/turbo")),
            ModCatalog.Entry(category: "Mods for Community Updates", name: "AM2R Hellrun", author: "DodoBirb",
                             summary: "AM2R 1.5.5 mod where all rooms outside of save points will deal damage to you. Move quickly to stay alive!",
                             link: URL(string: "https://example.com/hellrun")),
            ModCatalog.Entry(category: "Mods for Speedrunning", name: "Practice Mod", author: "Nommiin",
                             summary: "A mod based on YAL's reconstruction, used for speedrunning practice. Has savestates.", link: URL(string: "https://example.com/practice")),
        ]
        let current = Profile(name: "Community Updates 1.5.5", version: "1.5.5")
        current.lastPlayedAt = Date.now.addingTimeInterval(-3_600)
        current.playTime = 2 * 3_600 + 14 * 60
        current.patchCommit = String(repeating: "5", count: 40)
        context.insert(current)
        // The AM2R 1.1 copy those profiles were installed from.
        context.insert(GameSource(copy: AM2R11.Copy(url: URL(fileURLWithPath: "/tmp/AM2R_11.zip"), kind: .zip, root: "", hasWindowsGame: true)))
        try? context.save()
        model.selection = current.id
        // The game files a real install brings for Settings > Game: the language list.
        let lang = current.folder.appending(path: "lang", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: lang, withIntermediateDirectories: true)
        let names = ["english.ini": "English", "french.ini": "Français", "german.ini": "Deutsch", "japanese.ini": "Japanese"]
        try? names.keys.sorted { $0 == "english.ini" || ($1 != "english.ini" && $0 < $1) }.joined(separator: "\n")
            .write(to: lang.appending(path: "languages.txt"), atomically: true, encoding: .utf8)
        for (file, name) in names {
            try? "[Header]\nLanguage = \"\(name)\"\n".write(to: lang.appending(path: file), atomically: true, encoding: .utf8)
        }
    }
}
