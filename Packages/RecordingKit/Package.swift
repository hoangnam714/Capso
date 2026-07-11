// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RecordingKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "RecordingKit", targets: ["RecordingKit"])],
    dependencies: [.package(path: "../SharedKit")],
    targets: [
        .target(name: "RecordingKit", dependencies: ["SharedKit"]),
        .testTarget(name: "RecordingKitTests", dependencies: ["RecordingKit"]),
    ]
)
