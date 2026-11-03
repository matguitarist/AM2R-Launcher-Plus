import Foundation
import Testing
@testable import AM2RLauncherPlusKit

@Test("Clean profile names", arguments: [
    ("Community Updates 1.5.5", "Community Updates 1.5.5"),
    ("  Community   Updates \n", "Community Updates"),
    ("", "Community Updates"),
    ("   ", "Community Updates"),
])
func cleans(_ input: String, expected: String) {
    #expect(ProfileName.clean(input) == expected)
}

@Test func copyNamesAreUnique() {
    #expect(ProfileName.copy(of: "CU 1.5.5", existing: ["CU 1.5.5"]) == "CU 1.5.5 Copy")
    #expect(ProfileName.copy(of: "CU 1.5.5", existing: ["CU 1.5.5", "CU 1.5.5 Copy"]) == "CU 1.5.5 Copy 2")
    #expect(ProfileName.copy(of: "CU 1.5.5", existing: ["CU 1.5.5 Copy", "CU 1.5.5 Copy 2"]) == "CU 1.5.5 Copy 3")
}

@Test func keptSavesFoldersAreDatedAndSafe() {
    let date = Date(timeIntervalSince1970: 1_793_714_700) // 2026-11-03 14:05 UTC
    #expect(ProfileName.keptSavesFolder(for: "CU 1.5.5", date: date, timeZone: TimeZone(identifier: "UTC")!) == "CU 1.5.5 – 2026-11-03 14-05")
    #expect(ProfileName.keptSavesFolder(for: "a/b:c", date: date, timeZone: TimeZone(identifier: "UTC")!) == "a-b-c – 2026-11-03 14-05")
}
