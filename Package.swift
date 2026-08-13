// swift-tools-version: 5.9
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
    ],
    swiftLanguageVersions: [.v5]
)
