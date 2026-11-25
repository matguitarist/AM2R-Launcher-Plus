import ArchiveKit
import Foundation

/// Zipped copies of a profile's save folder (saves and config.ini), and putting one back (S-023), kept by
/// ArchiveKit's `BackupFolder`. A backup is a plain zip with the save files at its root, named
/// "<profile> – 2026-11-03 14-05.zip", "<profile> – 2026-11-03 14-05 (before restore).zip", then " 2", " 3"
/// when the name is taken.
public enum SaveBackup {
    public typealias Backup = BackupFolder.Backup

    public enum Failure: Error, Equatable, Sendable {
        case noSaves
        case notABackup
        case failed(String)

        public var message: String {
            switch self {
            case .noSaves: "This profile has no saves yet. Play once, then back up."
            case .notABackup: "This zip has no AM2R saves in it."
            case .failed(let reason): "Unable to finish: \(reason)"
            }
        }
    }

    /// The backups of one profile. A restore deletes the saves it replaces: the app backs them up first
    /// ("before restore") when there are any.
    static func folder(_ url: URL) -> BackupFolder { BackupFolder(root: url, disposal: .delete) }

    /// The backup's name without ".zip": "<profile> – <date>", then " (<label>)".
    static func name(profileName: String, label: String?, date: Date) -> String {
        let base = ProfileName.dated(profileName, date: date)
        return label.map { "\(base) (\($0))" } ?? base
    }

    /// Zips the contents of `saves` into `folder`. `label` is added to the name, e.g. "before restore".
    @discardableResult
    public static func backup(saves: URL, into folder: URL, profileName: String, label: String? = nil, date: Date = .now) async throws(Failure) -> URL {
        do {
            // The name is built here, so the label goes in parentheses rather than after BackupFolder's " - ".
            return try await self.folder(folder).backUp(from: saves, name: name(profileName: profileName, label: label, date: date),
                                                        date: date, macMetadata: false).url
        } catch ArchiveError.nothingToBackUp {
            throw .noSaves
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    /// The backups in `folder`, newest first.
    public static func list(in folder: URL) -> [Backup] {
        self.folder(folder).list()
    }

    /// Replaces the contents of `saves` with the backup. The zip is unpacked beside the save folder first
    /// and swapped in only when complete. A zip that holds one folder (a zipped save folder) works too.
    public static func restore(_ zip: URL, into saves: URL) async throws(Failure) {
        let backups = folder(zip.deletingLastPathComponent())
        guard let backup = try? backups.backup(at: zip) else { throw .notABackup }
        do {
            try await backups.restore(backup, into: saves, accept: { isSaveFolder($0) })
        } catch ArchiveError.notABackup {
            throw .notABackup
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    /// AM2R writes config.ini and save1…save3 (plus .bak and per-slot files) into its save folder.
    static func isSaveFolder(_ folder: URL) -> Bool {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map { $0.lowercased() }
        return names.contains { $0 == "config.ini" || $0.hasPrefix("save") }
    }
}
