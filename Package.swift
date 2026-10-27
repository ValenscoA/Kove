// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kove",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kove",
            path: "Sources/Kove",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
