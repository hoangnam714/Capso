// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AnnotationKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AnnotationKit", targets: ["AnnotationKit"])],
    dependencies: [.package(path: "../SharedKit")],
    targets: [
        .target(name: "AnnotationKit", dependencies: ["SharedKit"]),
        .testTarget(name: "AnnotationKitTests", dependencies: ["AnnotationKit"]),
    ]
)
