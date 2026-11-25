// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fdev",
    platforms: [.macOS(.v26)],   // Liquid Glass everywhere
    targets: [
        .executableTarget(
            name: "fdev",
            path: "Sources/fdev",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
