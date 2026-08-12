// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexCreditsMenubar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexCreditsMenubar", targets: ["CodexCreditsMenubar"])
    ],
    targets: [
        .executableTarget(name: "CodexCreditsMenubar", resources: [.process("Resources")]),
        .testTarget(name: "CodexCreditsMenubarTests", dependencies: ["CodexCreditsMenubar"])
    ]
)
