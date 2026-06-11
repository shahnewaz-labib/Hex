// swift-tools-version: 6.0
// Package.swift for Linux builds.
// On macOS, use the Xcode project (Hex.xcodeproj) instead.
//
// Build:
//   swift build -c release
//
// System dependencies:
//   - whisper-cpp  (apt install whisper-cpp)
//   - arecord      (apt install alsa-utils)
//   - xdotool      (apt install xdotool)
//   - xclip        (apt install xclip)
//   - pulseaudio   (apt install pulseaudio-utils, for paplay)
//   - xdg-utils    (apt install xdg-utils, for xdg-open)
import PackageDescription

let package = Package(
    name: "Hex",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hex", targets: ["HexLinux"]),
        .executable(name: "hex-hotkeyd", targets: ["HexHotkeyDaemon"]),
    ],
    dependencies: [
        .package(path: "HexCore"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.18.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
    ],
    targets: [
        .executableTarget(
            name: "HexLinux",
            dependencies: [
                "HexCore",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "HexLinux",
            exclude: ["HotkeyDaemon.swift", "models.json", "hex.desktop"]
        ),
        .executableTarget(
            name: "HexHotkeyDaemon",
            dependencies: [
                "HexCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "HexHotkeyDaemon"
        ),
    ]
)
