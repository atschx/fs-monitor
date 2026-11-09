// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FSMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FSMonitorCore", targets: ["FSMonitorCore"]),
        .executable(name: "FSMonitor", targets: ["FSMonitor"])
    ],
    targets: [
        .target(
            name: "FSMonitorCore",
            path: "Sources/FSMonitorCore"
        ),
        .target(
            name: "FSMonitorProc",
            path: "Sources/FSMonitorProc",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("proc", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "FSMonitor",
            dependencies: ["FSMonitorCore", "FSMonitorProc"],
            path: "Sources/FSMonitor"
        ),
        .testTarget(
            name: "FSMonitorCoreTests",
            dependencies: ["FSMonitorCore"],
            path: "Tests/FSMonitorCoreTests"
        )
    ]
)
