// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WoWBarsHelper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WoWBarsHelper", targets: ["WoWBarsHelper"]),
        .library(name: "StripKit", targets: ["StripKit"]),
    ],
    targets: [
        // Pure decoding of the on-screen strip (docs/strip-format.md). No AppKit.
        .target(name: "StripKit"),
        // The macOS app: capture, settings window, Dock / menu bar presentation.
        .executableTarget(
            name: "WoWBarsHelper",
            dependencies: ["StripKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StripKitTests",
            dependencies: ["StripKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
