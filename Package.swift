// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YTMusicCompanion",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YTMusicCompanion",
            path: "Sources/YTMusicCompanion",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YTMusicCompanionTests",
            dependencies: ["YTMusicCompanion"],
            path: "Tests/YTMusicCompanionTests"
        )
    ]
)
