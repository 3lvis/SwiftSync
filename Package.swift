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
        .library(name: "SwiftSync", targets: ["SwiftSync"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "SwiftDataBridge", targets: ["SwiftDataBridge"]),
        .library(name: "Macros", targets: ["Macros"]),
        .library(name: "TestingKit", targets: ["TestingKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest")
    ],
    targets: [
        .macro(
            name: "MacrosImplementation",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "SwiftSync/Sources/MacrosImplementation"
        ),
        .target(
            name: "Macros",
            dependencies: ["MacrosImplementation", "Core"],
            path: "SwiftSync/Sources/Macros"
        ),
        .target(
            name: "SwiftSync",
            dependencies: ["Core", "SwiftDataBridge", "Macros"],
            path: "SwiftSync/Sources/SwiftSync"
        ),
        .target(
            name: "Core",
            path: "SwiftSync/Sources/Core"
        ),
        .target(
            name: "SwiftDataBridge",
            dependencies: ["Core"],
            path: "SwiftSync/Sources/SwiftDataBridge"
        ),
        .target(
            name: "TestingKit",
            dependencies: ["Core"],
            path: "SwiftSync/Sources/TestingKit"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "SwiftSync/Tests/CoreTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SwiftSync"],
            path: "SwiftSync/Tests/IntegrationTests"
        )
    ]
)
