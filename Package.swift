// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WuwaAutoMover",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "WuwaAutoMoverCore", targets: ["WuwaAutoMoverCore"]),
        .executable(name: "WuwaAutoMoverGUI", targets: ["WuwaAutoMoverGUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(name: "WuwaAutoMoverCore"),
        .executableTarget(
            name: "WuwaAutoMoverGUI",
            dependencies: [
                "WuwaAutoMoverCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "WuwaAutoMoverCoreTests",
            dependencies: ["WuwaAutoMoverCore"]
        )
    ]
)
