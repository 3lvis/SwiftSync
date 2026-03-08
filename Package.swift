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
        .library(name: "DemoCore", targets: ["DemoCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
        .package(path: "DemoBackend")
    ],
    targets: [
        .macro(
            name: "MacrosImplementation",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ],
            path: "SwiftSync/Sources/MacrosImplementation"
        ),
        .target(
            name: "SwiftSync",
            dependencies: ["MacrosImplementation", "ObjCExceptionCatcher"],
            path: "SwiftSync/Sources/SwiftSync"
        ),
        .target(
            name: "ObjCExceptionCatcher",
            path: "SwiftSync/Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .target(
            name: "DemoCore",
            dependencies: [
                "SwiftSync",
                .product(name: "DemoBackend", package: "DemoBackend")
            ],
            path: "DemoCore/Sources/DemoCore",
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"]),
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        ),
        .testTarget(
            name: "SwiftSyncTests",
            dependencies: ["SwiftSync"],
            path: "SwiftSync/Tests/SwiftSyncTests"
        ),
        .testTarget(
            name: "DemoCoreTests",
            dependencies: ["DemoCore", "SwiftSync"],
            path: "DemoCore/Tests/DemoCoreTests"
        ),
        .testTarget(
            name: "SwiftSyncMacrosTests",
            dependencies: [
                "MacrosImplementation",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ],
            path: "SwiftSync/Tests/SwiftSyncMacrosTests"
        )
    ]
)
