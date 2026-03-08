// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DemoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DemoCore", targets: ["DemoCore"])
    ],
    dependencies: [
        .package(path: "../"),
        .package(path: "../DemoBackend")
    ],
    targets: [
        .target(
            name: "DemoCore",
            dependencies: [
                .product(name: "SwiftSync", package: "SwiftSync"),
                .product(name: "DemoBackend", package: "DemoBackend")
            ],
            path: "Sources/DemoCore",
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"]),
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        ),
        .testTarget(
            name: "DemoCoreTests",
            dependencies: ["DemoCore", .product(name: "SwiftSync", package: "SwiftSync")],
            path: "Tests/DemoCoreTests"
        )
    ]
)
