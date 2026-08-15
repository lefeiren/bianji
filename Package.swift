// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenMarker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScreenMarker", targets: ["ScreenMarker"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenMarker",
            path: "Sources/ScreenMarker"
        )
    ]
)
