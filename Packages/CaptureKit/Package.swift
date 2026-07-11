// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CaptureKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CaptureKit", targets: ["CaptureKit"])],
    dependencies: [.package(path: "../SharedKit")],
    targets: [
        .target(name: "CaptureKit", dependencies: ["SharedKit"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
