// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HexCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "HexCore", targets: ["HexCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Clipy/Sauce", from: "2.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
    ],
    targets: [
        .target(
            name: "HexCore",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Sauce", package: "Sauce", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/HexCore",
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "HexCoreTests",
            dependencies: ["HexCore"],
            path: "Tests/HexCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
