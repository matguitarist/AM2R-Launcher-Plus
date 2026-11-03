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
