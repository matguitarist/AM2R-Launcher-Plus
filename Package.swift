// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AM2RLauncherPlus",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Launcher updates (S-032). build.sh embeds Sparkle.framework in Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.6.0"),
        // Every command the launcher runs (the engine, codesign, osascript), shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/ProcessKit", from: "0.1.1"),
        // Zips and .7z in, save backups out, with Zip Slip checks; shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/ArchiveKit", from: "0.1.1"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "AM2RLauncherPlusKit", dependencies: [.product(name: "LogKit", package: "LogKit"),
                                                     .product(name: "ProcessKit", package: "ProcessKit"), .product(name: "ArchiveKit", package: "ArchiveKit")]),
        .executableTarget(
            name: "AM2RLauncherPlus",
            dependencies: ["AM2RLauncherPlusKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit"), .product(name: "ProcessKit", package: "ProcessKit")],
            // The Play page's header: an in-game screenshot of AM2R (README, Credits).
            resources: [.copy("Resources/Header.heic")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AM2RLauncherPlusKitTests", dependencies: ["AM2RLauncherPlusKit", .product(name: "LogKit", package: "LogKit"),
                                                                 .product(name: "ProcessKit", package: "ProcessKit"), .product(name: "ArchiveKit", package: "ArchiveKit")]),
    ]
)
