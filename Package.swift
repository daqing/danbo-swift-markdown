// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "danbo-swift-markdown",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DanboSwiftMarkdown", targets: ["DanboSwiftMarkdown"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.8.0"),
        .package(path: "../danbo-swift-highlight")
    ],
    targets: [
        .target(name: "DanboSwiftMarkdown", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "DanboSwiftHighlight", package: "danbo-swift-highlight")
        ]),
        .testTarget(name: "DanboSwiftMarkdownTests", dependencies: [
            "DanboSwiftMarkdown",
            // 测试要自己构造配色（`HighlightTheme.paired`）；库本身不 re-export 它。
            .product(name: "DanboSwiftHighlight", package: "danbo-swift-highlight")
        ])
    ],
    swiftLanguageModes: [.v5]
)
