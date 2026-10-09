// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Twang",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Twang", targets: ["Twang"]),
        .library(name: "TwangCore", targets: ["TwangCore"]),
    ],
    targets: [
        .target(
            name: "TwangCore",
            path: "Sources/TwangCore"
        ),
        .executableTarget(
            name: "Twang",
            dependencies: ["TwangCore"],
            path: "Sources/Twang"
        ),
        .testTarget(
            name: "TwangTests",
            dependencies: ["TwangCore"],
            path: "Tests/TwangTests"
        ),
    ]
)
