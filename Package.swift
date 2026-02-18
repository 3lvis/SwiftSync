// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftSync",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SwiftSyncCore", targets: ["SwiftSyncCore"]),
        .library(name: "SwiftSyncSwiftData", targets: ["SwiftSyncSwiftData"]),
        .library(name: "SwiftSyncTesting", targets: ["SwiftSyncTesting"]),
        .executable(name: "SwiftSyncDemo", targets: ["SwiftSyncDemo"])
    ],
    targets: [
        .target(
            name: "SwiftSyncCore"
        ),
        .target(
            name: "SwiftSyncSwiftData",
            dependencies: ["SwiftSyncCore"]
        ),
        .target(
            name: "SwiftSyncTesting",
            dependencies: ["SwiftSyncCore"]
        ),
        .executableTarget(
            name: "SwiftSyncDemo",
            dependencies: ["SwiftSyncCore", "SwiftSyncSwiftData", "SwiftSyncTesting"]
        ),
        .testTarget(
            name: "SwiftSyncCoreTests",
            dependencies: ["SwiftSyncCore"]
        ),
        .testTarget(
            name: "SwiftSyncXCTestSuite",
            dependencies: ["SwiftSyncCore", "SwiftSyncSwiftData"]
        )
    ]
)
