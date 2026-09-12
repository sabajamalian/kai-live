// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KaiLive",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KaiLive", targets: ["KaiLive"])
    ],
    targets: [
        .executableTarget(
            name: "KaiLive",
            path: "Sources/KaiLive"
        ),
        .testTarget(
            name: "KaiLiveTests",
            dependencies: ["KaiLive"],
            path: "Tests/KaiLiveTests"
        )
    ]
)
