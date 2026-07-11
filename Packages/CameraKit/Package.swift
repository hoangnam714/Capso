// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CameraKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CameraKit", targets: ["CameraKit"])],
    dependencies: [.package(path: "../SharedKit")],
    targets: [
        .target(name: "CameraKit", dependencies: ["SharedKit"]),
        .testTarget(name: "CameraKitTests", dependencies: ["CameraKit"]),
    ]
)
