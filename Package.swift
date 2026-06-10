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
import PackageDescription

let package = Package(
    name: "Hex",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "hex", targets: ["HexLinux"]),
    ],
    dependencies: [
        .package(path: "HexCore"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.18.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
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
            ],
            path: "HexLinux",
            sources: ["."]
        ),
    ]
)
