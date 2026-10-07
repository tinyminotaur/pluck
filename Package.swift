// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pluck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pluck", targets: ["Pluck"]),
        .library(name: "PluckCore", targets: ["PluckCore"]),
    ],
    targets: [
        .target(
            name: "PluckCore",
            path: "Sources/PluckCore"
        ),
        .executableTarget(
            name: "Pluck",
            dependencies: ["PluckCore"],
            path: "Sources/Pluck"
        ),
        .testTarget(
            name: "PluckTests",
            dependencies: ["PluckCore"],
            path: "Tests/PluckTests"
        ),
    ]
)
