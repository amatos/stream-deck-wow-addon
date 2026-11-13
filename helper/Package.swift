// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WoWBarsHelper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WoWBarsHelper", targets: ["WoWBarsHelper"]),
        .library(name: "StripKit", targets: ["StripKit"]),
        .library(name: "IconKit", targets: ["IconKit"]),
    ],
    targets: [
        // Pure decoding of the on-screen strip (docs/strip-format.md). No AppKit.
        .target(name: "StripKit"),
        // CascLib (vendored, MIT) plus a small C bridge, for reading the local WoW install.
        .target(
            name: "CascBridge",
            path: "Vendor/CascLib",
            exclude: ["LICENSE", "VERSION", "src/overwatch/cmf-key.cpp"],
            sources: ["src", "bridge"],
            publicHeadersPath: "include",
            cSettings: [
                .define("CASC_USE_SYSTEM_ZLIB"),
                .define("CASCLIB_NO_AUTO_LINK_LIBRARY"),
                .define("CASCLIB_NODEBUG"),
                .unsafeFlags(["-w"]),
            ],
            cxxSettings: [
                .define("CASC_USE_SYSTEM_ZLIB"),
                .define("CASCLIB_NO_AUTO_LINK_LIBRARY"),
                .define("CASCLIB_NODEBUG"),
                .unsafeFlags(["-w"]),
            ],
            linkerSettings: [.linkedLibrary("z")]
        ),
        // Icons: BLP decoding, install discovery and reading files by ID.
        .target(name: "IconKit", dependencies: ["CascBridge"]),
        // The macOS app: capture, settings window, Dock / menu bar presentation.
        .executableTarget(
            name: "WoWBarsHelper",
            dependencies: ["StripKit", "IconKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StripKitTests",
            dependencies: ["StripKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "IconKitTests", dependencies: ["IconKit"]),
    ],
    cxxLanguageStandard: .cxx17
)
