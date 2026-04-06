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
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b8670/llama-b8670-xcframework.zip",
            checksum: "79aeecd75edc7fbe48c0ad66b786f5ea34923d3772ce3bcd39ef69449e8d921c"
        ),
        .testTarget(
            name: "CopyCopyTests",
            dependencies: ["CopyCopy"],
            path: "Tests"
        )
    ]
)
