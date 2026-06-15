// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WuwaAutoMover",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "WuwaAutoMoverCore", targets: ["WuwaAutoMoverCore"]),
        .executable(name: "wuwa-auto-mover", targets: ["wuwa-auto-mover"]),
        .executable(name: "WuwaAutoMoverGUI", targets: ["WuwaAutoMoverGUI"])
    ],
    targets: [
        .target(name: "WuwaAutoMoverCore"),
        .executableTarget(
            name: "wuwa-auto-mover",
            dependencies: ["WuwaAutoMoverCore"]
        ),
        .executableTarget(
            name: "WuwaAutoMoverGUI",
            dependencies: ["WuwaAutoMoverCore"]
        )
    ]
)
