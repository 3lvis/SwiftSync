// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DemoBackend",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DemoBackend", targets: ["DemoBackend"])
    ],
    targets: [
        .target(
            name: "DemoBackend",
            path: "Sources/DemoBackend"
        ),
        .testTarget(
            name: "DemoBackendTests",
            dependencies: ["DemoBackend"],
            path: "Tests/DemoBackendTests"
        )
    ]
)
