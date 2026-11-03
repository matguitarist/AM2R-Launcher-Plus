// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AM2RLauncherPlus",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "AM2RLauncherPlusKit"),
        .executableTarget(
            name: "AM2RLauncherPlus",
            dependencies: ["AM2RLauncherPlusKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AM2RLauncherPlusKitTests", dependencies: ["AM2RLauncherPlusKit"]),
    ]
)
