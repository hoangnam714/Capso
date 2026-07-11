// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OCRKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OCRKit", targets: ["OCRKit"])],
    dependencies: [.package(path: "../SharedKit")],
    targets: [
        .target(name: "OCRKit", dependencies: ["SharedKit"]),
        .testTarget(name: "OCRKitTests", dependencies: ["OCRKit"]),
    ]
)
