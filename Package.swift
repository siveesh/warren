// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SKMole",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "SKMoleShared",
            targets: ["SKMoleShared"]
        ),
        .executable(
            name: "SKMoleApp",
            targets: ["SKMoleApp"]
        ),
        .executable(
            name: "SKMolePrivilegedHelper",
            targets: ["SKMolePrivilegedHelper"]
        ),
        .executable(
            name: "SKMoleMenuBarHelper",
            targets: ["SKMoleMenuBarHelper"]
        ),
        .executable(
            name: "SKMoleWidgets",
            targets: ["SKMoleWidgets"]
        )
    ],
    dependencies: [
        // Relay command palette and workflow engine (bundled copy of the standalone Relay app's core).
        .package(path: "Packages/RelayKit"),
        // Application inventory, leftovers, orphans, receipts, Homebrew and removal logic ported from Peel (GPL-3.0-or-later).
        .package(path: "Packages/PeelCore")
    ],
    targets: [
        .target(
            name: "SKMoleShared",
            path: "Sources/SKMoleShared"
        ),
        .executableTarget(
            name: "SKMoleApp",
            dependencies: [
                "SKMoleShared",
                .product(name: "RelayAppSupport", package: "RelayKit"),
                .product(name: "RelayCore", package: "RelayKit"),
                .product(name: "RelayUI", package: "RelayKit"),
                .product(name: "RelaySecurity", package: "RelayKit"),
                .product(name: "RelayTasks", package: "RelayKit"),
                .product(name: "RelayCommandPacks", package: "RelayKit"),
                .product(name: "PeelCore", package: "PeelCore"),
                .product(name: "PeelPrivileged", package: "PeelCore")
            ],
            path: "Sources/SKMoleApp"
        ),
        .executableTarget(
            name: "SKMolePrivilegedHelper",
            dependencies: [
                "SKMoleShared",
                .product(name: "PeelPrivileged", package: "PeelCore")
            ],
            path: "Sources/SKMolePrivilegedHelper",
            linkerSettings: [
                // The helper's signature binds this Info.plist, and the app requires a build no older than the helper's.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Bundling/PrivilegedHelper-Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "SKMoleMenuBarHelper",
            dependencies: [
                "SKMoleShared",
                .product(name: "RelayAppSupport", package: "RelayKit"),
                .product(name: "RelayCore", package: "RelayKit"),
                .product(name: "RelayUI", package: "RelayKit")
            ],
            path: "Sources/SKMoleMenuBarHelper"
        ),
        .executableTarget(
            name: "SKMoleWidgets",
            dependencies: ["SKMoleShared"],
            path: "Sources/SKMoleWidgets",
            linkerSettings: [
                // A widget extension starts in the extension runtime, not in main.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "SKMoleAppTests",
            dependencies: ["SKMoleApp", "SKMoleShared"],
            path: "Tests/SKMoleAppTests"
        )
    ]
)
