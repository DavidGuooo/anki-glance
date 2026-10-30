// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlanceCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .testTarget(
            name: "GlanceCoreTests",
            dependencies: ["GlanceCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
