// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "meister-cli",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "meister", targets: ["meister"]),
        .library(name: "MeisterKit", targets: ["MeisterKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MeisterKit",
            path: "Sources/MeisterKit"
        ),
        .executableTarget(
            name: "meister",
            dependencies: [
                "MeisterKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/meister"
        ),
        .testTarget(
            name: "MeisterKitTests",
            dependencies: ["MeisterKit"],
            path: "Tests/MeisterKitTests"
        ),
    ]
)
