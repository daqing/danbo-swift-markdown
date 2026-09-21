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
    targets: [
        .target(name: "DanboSwiftMarkdown"),
        .testTarget(name: "DanboSwiftMarkdownTests", dependencies: ["DanboSwiftMarkdown"])
    ],
    swiftLanguageModes: [.v5]
)
