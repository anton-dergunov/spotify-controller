// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Harmonic",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Harmonic", targets: ["Harmonic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Harmonic",
            dependencies: ["HotKey"],
            path: "Sources/Harmonic",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
