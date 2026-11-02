// swift-tools-version: 6.2
//
// Unit tests for Chrono's pure logic: persistence (encode/decode, migration,
// failed-load backups), time math, idle auto-pause and the status item toggle.
//
// The sources are symlinks to the app's real files in ../../Chrono, so the
// tests always exercise the shipped code. Run from the repo root:
//
//     swift test --package-path Tests/ChronoCore
//
import PackageDescription

let package = Package(
    name: "ChronoCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ChronoCore",
            swiftSettings: [
                // Mirror the app target (SWIFT_VERSION 5.9, default MainActor isolation).
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "ChronoCoreTests",
            dependencies: ["ChronoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
