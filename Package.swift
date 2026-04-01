// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopyCopy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CopyCopy", targets: ["CopyCopy"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.2.2"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "CopyCopy",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "CopyCopyTests",
            dependencies: ["CopyCopy"],
            path: "Tests"
        )
    ]
)

