import Foundation

/// The community's list of AM2R mods (gitlab.com/Miepee/AM2R-Mods), read from its README:
/// `# Mods for …` groups, `## <Name> by <Authors>` entries, a description, and download links.
public enum ModCatalog {
    public static let readme = URL(string: "https://gitlab.com/Miepee/AM2R-Mods/-/raw/main/README.md")!
    public static let page = URL(string: "https://gitlab.com/Miepee/AM2R-Mods")!

    public struct Entry: Equatable, Hashable, Sendable, Identifiable {
        public var category: String
        public var name: String
        public var author: String
        public var summary: String
        /// The download link, or else the first link in the entry.
        public var link: URL?
        public var id: String { category + "/" + name }

        public init(category: String, name: String, author: String, summary: String, link: URL?) {
            self.category = category
            self.name = name
            self.author = author
            self.summary = summary
            self.link = link
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case offline, unreadable
        public var message: String {
            switch self {
            case .offline: "Unable to reach the mod list. Check your connection."
            case .unreadable: "The mod list has an unexpected format."
            }
        }
    }

    public static func fetch(session: URLSession = .shared) async throws(Failure) -> [Entry] {
        var request = URLRequest(url: readme, timeoutInterval: 15)
        request.setValue("AM2RLauncherPlus", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.offline }
            data = body
        } catch {
            throw .offline
        }
        let entries = parse(String(decoding: data, as: UTF8.self))
        if entries.isEmpty { throw .unreadable }
        return entries
    }

    public static func parse(_ markdown: String) -> [Entry] {
        var entries: [Entry] = []
        var category: String?
        var current: (name: String, author: String, lines: [String])?

        func finish() {
            guard let current, let category else { return }
            let links = current.lines.flatMap(Self.links)
            let download = current.lines.first { $0.localizedCaseInsensitiveContains("download") }.flatMap { Self.links(in: $0).first }
            let paragraph = current.lines
                .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .filter { !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("download") }
                .map { plain($0).trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            // A heading with nothing to download is a note in the list, not a mod.
            guard let link = download ?? links.first else { return }
            entries.append(Entry(category: category, name: current.name, author: current.author, summary: paragraph, link: link))
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                finish()
                let title = plain(String(line.dropFirst(3))).trimmingCharacters(in: .whitespaces)
                if let by = title.range(of: " by ") {
                    current = (String(title[..<by.lowerBound]), String(title[by.upperBound...]), [])
                } else {
                    current = (title, "", [])
                }
            } else if line.hasPrefix("# ") {
                finish()
                current = nil
                category = plain(String(line.dropFirst(2))).trimmingCharacters(in: .whitespaces)
            } else if line == "---" {
                finish()
                current = nil
            } else if current != nil {
                current?.lines.append(raw)
            }
        }
        finish()
        return entries
    }

    /// Web links in a markdown line, skipping anchors inside the page.
    static func links(in line: String) -> [URL] {
        let pattern = /\[[^\]]*\]\((https?:[^)\s]+)\)/
        return line.matches(of: pattern).compactMap { URL(string: String($0.output.1)) }
    }

    /// Markdown to plain text: links keep their words, emphasis and code marks go.
    static func plain(_ text: String) -> String {
        text.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
            .replacing(/\*\*|__|`/, with: "")
            .replacing(/\*([^*\s][^*]*)\*/) { String($0.output.1) }
    }
}
