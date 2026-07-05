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
        .package(url: "https://github.com/jaredhowland/html-to-markdown-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.4"),
    ],
    targets: [
        .executableTarget(
            name: "CopyCopy",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "HTMLToMarkdown", package: "html-to-markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                "LlamaFramework",
            ],
            path: "Sources",
            resources: [
                .copy("Resources/Fonts")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Metal"),
                .linkedFramework("Accelerate"),
            ]
        ),
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b9542/llama-b9542-xcframework.zip",
            checksum: "10763c95e9c43b5d92d9f5a2f733d156695adfc11d014b1d76ae19906148cb4d"
        ),
        .testTarget(
            name: "CopyCopyTests",
            dependencies: ["CopyCopy"],
            path: "Tests"
        )
    ]
)
