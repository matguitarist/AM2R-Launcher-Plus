// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AM2RLauncherPlus",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Launcher updates (S-032). build.sh embeds Sparkle.framework in Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.4.1"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "AM2RLauncherPlusKit", dependencies: [.product(name: "LogKit", package: "LogKit")]),
        .executableTarget(
            name: "AM2RLauncherPlus",
            dependencies: ["AM2RLauncherPlusKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AM2RLauncherPlusKitTests", dependencies: ["AM2RLauncherPlusKit", .product(name: "LogKit", package: "LogKit")]),
    ]
)
