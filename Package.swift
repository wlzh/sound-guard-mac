// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SoundGuard", platforms: [.macOS("14.2")],
    products: [.executable(name: "SoundGuard", targets: ["SoundGuard"])],
    targets: [
        .target(name: "GuardCore"),
        .target(name: "SignalMeter", publicHeadersPath: "include"),
        .target(name: "GuardPlatform", dependencies: ["GuardCore", "SignalMeter"]),
        .executableTarget(name: "SoundGuard", dependencies: ["GuardCore", "GuardPlatform"]),
        .executableTarget(name: "GuardTests", dependencies: ["GuardCore", "GuardPlatform", "SignalMeter"], path: "Tests/GuardCoreTests")
    ]
)
