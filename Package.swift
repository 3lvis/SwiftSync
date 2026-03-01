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
        .library(name: "SwiftSync", targets: ["SwiftSync"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest")
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
        .testTarget(
            name: "CoreTests",
            dependencies: ["SwiftSync"],
            path: "SwiftSync/Tests/CoreTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SwiftSync"],
            path: "SwiftSync/Tests/IntegrationTests"
        ),
        .testTarget(
            name: "MacrosTests",
            dependencies: [
                "MacrosImplementation",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ],
            path: "SwiftSync/Tests/MacrosTests"
        )
    ]
)
