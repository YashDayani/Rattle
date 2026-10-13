// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rattle",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "Rattle",
            path: "Sources/Rattle"
        )
    ]
)
