// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "RelayKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "RelayCore", targets: ["RelayCore"]),
        .library(name: "RelayStorage", targets: ["RelayStorage"]),
        .library(name: "RelaySearch", targets: ["RelaySearch"]),
        .library(name: "RelayTasks", targets: ["RelayTasks"]),
        .library(name: "RelaySecurity", targets: ["RelaySecurity"]),
        .library(name: "RelayNotifications", targets: ["RelayNotifications"]),
        .library(name: "RelayCommandPacks", targets: ["RelayCommandPacks"]),
        .library(name: "RelayUI", targets: ["RelayUI"]),
        .library(name: "RelayAppSupport", targets: ["RelayAppSupport"]),
    ],
    targets: [
        // Root domain module — depends on nothing else in RelayKit.
        .target(name: "RelayCore"),

        .target(name: "RelayStorage", dependencies: ["RelayCore"]),
        .target(name: "RelaySearch", dependencies: ["RelayCore"]),
        .target(name: "RelayTasks", dependencies: ["RelayCore", "RelayNotifications"]),
        .target(name: "RelaySecurity", dependencies: ["RelayCore"]),
        .target(name: "RelayNotifications", dependencies: ["RelayCore"]),
        .target(name: "RelayCommandPacks", dependencies: ["RelayCore", "RelayStorage"]),
        .target(name: "RelayUI", dependencies: ["RelayCore"]),

        // Glue shared by the main app and the menu bar companion.
        .target(
            name: "RelayAppSupport",
            dependencies: [
                "RelayCore", "RelayStorage", "RelaySearch", "RelayTasks",
                "RelaySecurity", "RelayNotifications", "RelayCommandPacks", "RelayUI"
            ]
        ),

        // Tests.
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"]),
        .testTarget(name: "RelayStorageTests", dependencies: ["RelayStorage"]),
        .testTarget(name: "RelaySearchTests", dependencies: ["RelaySearch"]),
        .testTarget(name: "RelayCommandPacksTests", dependencies: ["RelayCommandPacks"]),
        .testTarget(name: "RelayTasksTests", dependencies: ["RelayTasks"]),
        .testTarget(name: "RelaySecurityTests", dependencies: ["RelaySecurity"]),
        .testTarget(name: "RelayUITests", dependencies: ["RelayUI", "RelaySearch"]),
    ]
)
