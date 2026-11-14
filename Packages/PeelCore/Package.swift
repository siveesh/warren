// swift-tools-version: 6.4
// Vendored from https://github.com/TuguiDragos/Peel (GPL-3.0-or-later), see UPSTREAM.md.
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "PeelCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PeelCore", targets: ["PeelCore"]),
        .library(name: "PeelPrivileged", targets: ["PeelPrivileged"]),
    ],
    targets: [
        .target(name: "PeelPrivileged", swiftSettings: swiftSettings),
        .target(name: "PeelCore", dependencies: ["PeelPrivileged"], swiftSettings: swiftSettings),
        .testTarget(
            name: "PeelCoreTests",
            dependencies: ["PeelCore", "PeelPrivileged"],
            swiftSettings: swiftSettings
        ),
    ]
)
