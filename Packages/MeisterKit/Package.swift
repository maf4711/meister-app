// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeisterKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MeisterKit", targets: ["MeisterKit"]),
    ],
    targets: [
        .target(
            name: "MeisterKit",
            path: "Sources/MeisterKit"
        ),
        .testTarget(
            name: "MeisterKitTests",
            dependencies: ["MeisterKit"]
        ),
    ]
)
