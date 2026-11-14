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
                .product(name: "PeelCore", package: "PeelCore")
            ],
            path: "Sources/SKMoleApp"
        ),
        .executableTarget(
            name: "SKMolePrivilegedHelper",
            dependencies: ["SKMoleShared"],
            path: "Sources/SKMolePrivilegedHelper"
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
        .testTarget(
            name: "SKMoleAppTests",
            dependencies: ["SKMoleApp", "SKMoleShared"],
            path: "Tests/SKMoleAppTests"
        )
    ]
)
