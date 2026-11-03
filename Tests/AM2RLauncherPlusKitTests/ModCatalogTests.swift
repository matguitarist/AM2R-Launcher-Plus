import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private let sample = """
# AM2R-Mods
Table of Contents:
<details>
<summary>[Mods for Speedrunning](#mods-for-speedrunning)</summary>

- [Practice Mod](#practice-mod-by-nommiin)
</details>

# Mods for Speedrunning

## Practice Mod by Nommiin
A mod based on YAL's reconstruction, used for **speedrunning** practice.
Download for [Windows](https://example.com/practice.zip?inline=false).

---

# Mods for Community Updates

## AM2R Turbo Edition by DodoBirb
A mod for AM2R 1.5.5 that adds `AimLock` speedbooster techniques, *only* for fun.
See the [repository](https://github.com/example/turbo) for more.

Download link for Windows [here](https://github.com/example/turbo/releases/latest).

## AM2R 1.6b2
Second beta of 1.6.
Download links (Win, Lin) can be found [here](https://github.com/example/16/releases/tag/1.6b2)
"""

@Test func readsTheModList() {
    let entries = ModCatalog.parse(sample)
    #expect(entries.map(\.name) == ["Practice Mod", "AM2R Turbo Edition", "AM2R 1.6b2"])
    #expect(entries.map(\.category) == ["Mods for Speedrunning", "Mods for Community Updates", "Mods for Community Updates"])
    #expect(entries[0].author == "Nommiin")
    #expect(entries[0].summary == "A mod based on YAL's reconstruction, used for speedrunning practice.")
    #expect(entries[0].link == URL(string: "https://example.com/practice.zip?inline=false"))
    // The download line wins over the first link, and markdown marks are gone.
    #expect(entries[1].link == URL(string: "https://github.com/example/turbo/releases/latest"))
    #expect(entries[1].summary == "A mod for AM2R 1.5.5 that adds AimLock speedbooster techniques, only for fun. See the repository for more.")
    #expect(entries[2].author == "")
    #expect(entries[2].summary == "Second beta of 1.6.")
}

@Test func emptyOrForeignTextHasNoMods() {
    #expect(ModCatalog.parse("").isEmpty)
    #expect(ModCatalog.parse("## Lonely entry without a group\ntext").isEmpty)
    #expect(ModCatalog.parse("# Mods for X\n## A note, not a mod\nNo links here.").isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"))
func readsTheRealModList() async throws {
    let entries = try await ModCatalog.fetch()
    #expect(entries.count > 30)
    #expect(entries.contains { $0.name.contains("Multitroid") })
    #expect(entries.allSatisfy { $0.link != nil })
}
