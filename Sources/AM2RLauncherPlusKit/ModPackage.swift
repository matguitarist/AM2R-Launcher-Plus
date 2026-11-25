import ArchiveKit
import Foundation

/// The attributes of an AM2RLauncher profile.xml, read by name with a real XML parser
/// (mod packers write XMLVersion="1" before Version="…", and notes carry entities).
public struct ProfileXML: Equatable, Sendable {
    public var attributes: [String: String]

    public init?(_ xml: String) {
        // The text is already decoded, so the declared encoding no longer applies: .NET writers that
        // serialize to a string declare utf-16 for a UTF-8 file, and the parser would then misread it.
        let xml = xml.replacing(/^(\s*<\?xml[^>]*?)\s+encoding\s*=\s*["'][^"']*["']/, with: { $0.output.1 })
        guard let data = xml.data(using: .utf8) else { return nil }
        let reader = RootAttributes()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() || reader.attributes != nil, let attributes = reader.attributes else { return nil }
        self.attributes = attributes
    }

    public subscript(_ name: String) -> String? { attributes[name] }

    /// "true"/"True"/"1" as GameMaker's launcher writes booleans.
    public func flag(_ name: String) -> Bool {
        guard let value = attributes[name]?.lowercased() else { return false }
        return value == "true" || value == "1"
    }

    public var name: String? { nonEmpty("Name") }
    public var version: String? { nonEmpty("Version") }
    public var author: String { attributes["Author"] ?? "" }
    public var notes: String { attributes["ProfileNotes"] ?? "" }
    public var operatingSystem: String { attributes["OperatingSystem"] ?? "" }
    public var usesYYC: Bool { flag("UsesYYC") }
    /// Installable="false" marks archived Community Updates profiles that AM2RLauncher only lists.
    /// Older mod packers leave it out, so a missing value means installable.
    public var installable: Bool { attributes["Installable"] == nil || flag("Installable") }

    private func nonEmpty(_ name: String) -> String? {
        guard let value = attributes[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Keeps the first element's attributes and stops.
    private final class RootAttributes: NSObject, XMLParserDelegate {
        var attributes: [String: String]?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if attributes == nil {
                attributes = attributeDict
                parser.abortParsing()
            }
        }
    }
}

/// An AM2RLauncher mod zip (S-033): profile.xml, a patch of AM2R 1.1's data.win
/// (game.xdelta for Linux and Mac, data.xdelta for Windows), and files_to_copy/.
public struct ModPackage: Equatable, Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case unreadable
        case notAMod
        case yyc(name: String)
        case noGamePatch(name: String)
        case builtOnAM2R11(name: String)
        case notInstallable(name: String)

        public var message: String {
            switch self {
            case .unreadable: "Unable to open this zip."
            case .notAMod: "This zip isn't an AM2R mod. It has no profile.xml."
            case .yyc(let name): "\(name) is built with YYC, so it only runs with its own Windows runner."
            case .noGamePatch(let name): "\(name) has no patch for the game data."
            case .builtOnAM2R11(let name): "\(name) is built on AM2R 1.1, which plays badly here. Mods built on Community Updates 1.5 or later work."
            case .notInstallable(let name): "\(name) is an archived profile that can't be installed."
            }
        }
    }

    /// Whether a patched game is built on Community Updates (1.5 and later) rather than AM2R 1.1:
    /// its code reads config.ini's LowHealthWarning, an option Community Updates added.
    /// AM2R 1.1's older code hits more engine gaps, so mods built on it are refused.
    public static func isBuiltOnCommunityUpdates(game: URL) -> Bool {
        guard let data = try? Data(contentsOf: game, options: .alwaysMapped) else { return false }
        return data.range(of: Data("LowHealthWarning".utf8)) != nil
    }

    public var zip: URL
    /// The folder inside the zip that holds profile.xml: "" or "Some Mod/".
    public var root: String
    public var profile: ProfileXML
    /// game.xdelta or data.xdelta, relative to `root`.
    public var gamePatch: String
    public var hasFilesToCopy: Bool

    public var name: String { profile.name ?? zip.deletingPathExtension().lastPathComponent }
    public var version: String { profile.version ?? "" }
    public var author: String { profile.author }

    /// The most profile.xml may weigh: its notes are text.
    static let profileLimit = 16 << 20

    /// Reads the zip's table of contents and its profile.xml, without extracting anything else.
    public static func read(_ zip: URL) async throws(Failure) -> ModPackage {
        let all: [Zip.Entry]
        do { all = try Zip.entries(zip) } catch { throw .unreadable }
        // Refuses paths that would land outside the extraction folder, and links pointing out of it.
        if Zip.unsafeEntry(all) != nil { throw .unreadable }
        let entries = all.map(\.name)
            .filter { !$0.hasPrefix("__MACOSX/") && !$0.contains("/._") && !$0.hasPrefix("._") }
        guard let path = profilePath(in: entries) else { throw .notAMod }
        let root = String(path.dropLast("profile.xml".count))
        guard let data = try? await Zip.read(path, from: zip, limit: profileLimit),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let profile = ProfileXML(text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")))
        else { throw .notAMod }
        let name = profile.name ?? zip.deletingPathExtension().lastPathComponent
        if !profile.installable { throw .notInstallable(name: name) }
        if profile.usesYYC { throw .yyc(name: name) }
        guard let patch = gamePatch(in: entries, root: root) else { throw .noGamePatch(name: name) }
        return ModPackage(zip: zip, root: root, profile: profile, gamePatch: patch,
                          hasFilesToCopy: entries.contains { $0.hasPrefix(root + "files_to_copy/") })
    }

    /// profile.xml at the top, or one folder down when the mod was zipped with its folder.
    static func profilePath(in entries: [String]) -> String? {
        let candidates = entries.filter { $0 == "profile.xml" || $0.hasSuffix("/profile.xml") }
            .filter { $0.split(separator: "/").count <= 2 }
        return candidates.min { $0.count < $1.count }
    }

    /// game.xdelta is made for Unix data files, closest to the Mac; data.xdelta is the Windows one.
    static func gamePatch(in entries: [String], root: String) -> String? {
        for name in ["game.xdelta", "data.xdelta"] where entries.contains(root + name) {
            return name
        }
        return nil
    }

    /// Extracts the mod's folder (everything under `root`) into `folder`, which then holds profile.xml.
    public func extract(into folder: URL) async throws(Failure) {
        let fm = FileManager.default
        let work = folder.appending(path: ".unzip", directoryHint: .isDirectory)
        try? fm.removeItem(at: work)
        defer { try? fm.removeItem(at: work) }
        do { try await Zip.unpack(zip, into: work, dropsQuarantine: true) } catch { throw .unreadable }
        let base = root.isEmpty ? work : work.appending(path: root, directoryHint: .isDirectory)
        do {
            for item in try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) where item.lastPathComponent != "__MACOSX" {
                let target = folder.appending(path: item.lastPathComponent)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: item, to: target)
            }
        } catch {
            throw .unreadable
        }
    }
}
