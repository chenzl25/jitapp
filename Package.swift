// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fanyiapp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Floating "drag Jit into this list" helper next to System Settings.
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", from: "2.11.4"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "fanyiapp",
            dependencies: [
                "JitCLI",
                "JitText",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ],
            path: "Sources",
            exclude: ["JitCLI", "JitText"]),
        .target(name: "JitCLI", path: "Sources/JitCLI"),
        .target(name: "JitText", path: "Sources/JitText"),
        .testTarget(name: "JitCLITests", dependencies: ["JitCLI"]),
        .testTarget(name: "JitTextTests", dependencies: ["JitText"]),
    ]
)
