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
        .package(path: "../DemoBackend"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
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
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "DemoCoreTests",
            dependencies: ["DemoCore", .product(name: "SwiftSync", package: "SwiftSync")],
            path: "Tests/DemoCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
