// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlackmagicControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BlackmagicControl",
            path: "Sources/BlackmagicControl",
            swiftSettings: [
                // Relaxed concurrency keeps the SwiftUI/URLSession glue simple.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
