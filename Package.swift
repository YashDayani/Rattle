// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rattle",
    platforms: [.macOS("14.4")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.8.2"),
    ],
    targets: [
        .executableTarget(
            name: "Rattle",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Rattle"
        ),
        .testTarget(name: "RattleTests", dependencies: ["Rattle"], path: "Tests/RattleTests")
    ]
)
