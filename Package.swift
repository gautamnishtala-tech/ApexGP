// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ApexGP",
    platforms: [.macOS(.v14)],
    targets: [
        // Game logic: track, physics, race rules, in-game agents. No UI imports.
        .target(name: "ApexGPCore"),
        // SceneKit/AppKit front end: rendering, input, HUD, audio.
        .executableTarget(name: "ApexGPApp", dependencies: ["ApexGPCore"]),
        .testTarget(name: "ApexGPCoreTests", dependencies: ["ApexGPCore"]),
    ]
)
