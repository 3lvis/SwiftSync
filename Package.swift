// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftSync",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SwiftSyncCore", targets: ["SwiftSyncCore"]),
        .library(name: "SwiftSyncSwiftData", targets: ["SwiftSyncSwiftData"]),
        .library(name: "SwiftSyncMacros", targets: ["SwiftSyncMacros"]),
        .library(name: "SwiftSyncTesting", targets: ["SwiftSyncTesting"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest")
    ],
    targets: [
        .macro(
            name: "SwiftSyncMacrosImplementation",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SwiftSyncMacros",
            dependencies: ["SwiftSyncMacrosImplementation", "SwiftSyncCore"]
        ),
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
        .testTarget(
            name: "SwiftSyncCoreTests",
            dependencies: ["SwiftSyncCore"]
        ),
        .testTarget(
            name: "SwiftSyncXCTestSuite",
            dependencies: ["SwiftSyncCore", "SwiftSyncSwiftData", "SwiftSyncMacros"]
        )
    ]
)
