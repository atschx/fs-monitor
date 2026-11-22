// swift-tools-version: 5.9
import PackageDescription

// User-initiated one-shot adapter. Only the audited scanner/model slice is compiled; no monitors/probes.
let package = Package(
    name: "DemoFirstScreen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DemoFirstScreenCore", targets: ["DemoFirstScreenCore"]),
        .executable(name: "DemoFirstScreen", targets: ["DemoFirstScreenApp"]),
        .executable(name: "DemoRasterBenchmark", targets: ["DemoRasterBenchmark"])
    ],
    targets: [
        .target(name:"ReadOnlyScanner"),
        .target(name:"FolderSnapshotAdapter",dependencies:["ReadOnlyScanner","DemoFirstScreenCore"]),
        .testTarget(name:"FolderSnapshotTests",dependencies:["FolderSnapshotAdapter","ReadOnlyScanner","DemoFirstScreenCore"]),
        .target(name:"EyeStudySupport",dependencies:["DemoFirstScreenCore"]),
        .testTarget(name:"EyeStudySupportTests",dependencies:["EyeStudySupport","DemoFirstScreenCore"]),
        .target(
            name: "DemoFirstScreenCore",
            dependencies: [],
            path: "Sources/DemoFirstScreenCore",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "DemoFirstScreenApp",
            dependencies: ["DemoFirstScreenCore","EyeStudySupport","FolderSnapshotAdapter"],
            path: "Sources/DemoFirstScreenApp",resources:[.copy("Resources")]
        ),
        .executableTarget(
            name: "DemoRasterBenchmark", dependencies: ["DemoFirstScreenCore"],
            path: "Sources/DemoRasterBenchmark"
        ),
        .testTarget(
            name: "DemoFirstScreenCoreTests",
            dependencies: ["DemoFirstScreenCore"],
            path: "Tests/DemoFirstScreenCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
