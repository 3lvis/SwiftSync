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
            path: "Sources/MacrosImplementation"
        ),
        .target(
            name: "Macros",
            dependencies: ["MacrosImplementation", "Core"],
            path: "Sources/Macros"
        ),
        .target(
            name: "SwiftSync",
            dependencies: ["Core", "SwiftDataBridge", "Macros"],
            path: "Sources/SwiftSync"
        ),
        .target(
            name: "Core",
            path: "Sources/Core"
        ),
        .target(
            name: "SwiftDataBridge",
            dependencies: ["Core"],
            path: "Sources/SwiftDataBridge"
        ),
        .target(
            name: "TestingKit",
            dependencies: ["Core"],
            path: "Sources/TestingKit"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SwiftSync"],
            path: "Tests/IntegrationTests"
        )
    ]
)
