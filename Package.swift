// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SpeedWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpeedWidget", targets: ["SpeedWidgetApp"])
    ],
    targets: [
        .target(
            name: "SpeedWidgetCore",
            path: "Sources/SpeedWidgetCore"
        ),
        .executableTarget(
            name: "SpeedWidgetApp",
            dependencies: ["SpeedWidgetCore"],
            path: "Sources/SpeedWidgetApp"
        ),
        .testTarget(
            name: "SpeedWidgetCoreTests",
            dependencies: ["SpeedWidgetCore"],
            path: "Tests/SpeedWidgetCoreTests"
        )
    ]
)
