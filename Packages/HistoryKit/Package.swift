// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HistoryKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "HistoryKit", targets: ["HistoryKit"])],
    dependencies: [
        .package(path: "../SharedKit"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.4.1"),
    ],
    targets: [
        .target(
            name: "HistoryKit",
            dependencies: [
                "SharedKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "HistoryKitTests", dependencies: ["HistoryKit"]),
    ]
)
