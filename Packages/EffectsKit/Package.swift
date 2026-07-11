// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "EffectsKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "EffectsKit", targets: ["EffectsKit"])],
    dependencies: [.package(path: "../SharedKit")],
    targets: [
        .target(name: "EffectsKit", dependencies: ["SharedKit"]),
        .testTarget(name: "EffectsKitTests", dependencies: ["EffectsKit"]),
    ]
)
