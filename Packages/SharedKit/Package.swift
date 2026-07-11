// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"]),
    ],
    targets: [
        .target(
            name: "SharedKit",
            dependencies: []
        ),
        .testTarget(
            name: "SharedKitTests",
            dependencies: ["SharedKit"]
        ),
    ]
)
