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
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.8.0")
    ],
    targets: [
        .target(name: "DanboSwiftMarkdown", dependencies: [
            .product(name: "Markdown", package: "swift-markdown")
        ]),
        .testTarget(name: "DanboSwiftMarkdownTests", dependencies: ["DanboSwiftMarkdown"])
    ],
    swiftLanguageModes: [.v5]
)
