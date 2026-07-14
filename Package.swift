// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YTMusicCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YTMusicCompanion",
            path: "Sources/YTMusicCompanion",
            resources: [.copy("Resources/tray-icon.png")]
        ),
        .testTarget(
            name: "YTMusicCompanionTests",
            dependencies: ["YTMusicCompanion"],
            path: "Tests/YTMusicCompanionTests"
        )
    ]
)
