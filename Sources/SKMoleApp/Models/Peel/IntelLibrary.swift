// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import PeelCore

/// Software on this Mac that contains Intel code, found by the engine ported from Peel: apps, the programs inside
/// them, plug-ins, drivers, background items, command-line tools and Java runtimes.
@MainActor
@Observable
final class IntelLibrary {
    private(set) var scan: IntelScan?
    private(set) var isScanning = false

    private let apps: AppLibrary
    private let removal: RemovalService

    init(apps: AppLibrary, removal: RemovalService) {
        self.removal = removal
        self.apps = apps
    }

    var findings: [IntelFinding] { scan?.findings ?? [] }

    var isAppleSilicon: Bool { HostArchitecture.isAppleSilicon }
    var rosettaInstalled: Bool { Rosetta.isInstalled }

    func findings(of kind: IntelFinding.Kind) -> [IntelFinding] {
        scan?.findings(of: kind) ?? []
    }

    func rescanIfNeeded() async {
        if scan == nil { await rescan() }
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true

        if apps.apps.isEmpty { await apps.rescan() }
        let installed = apps.apps
        let exclusions = removal.exclusions

        async let backgroundItems = BackgroundItems.scan(installedApps: installed, exclusions: exclusions)
        scan = await IntelInspector.scan(installedApps: installed, backgroundItems: backgroundItems, exclusions: exclusions)
        isScanning = false
    }
}

extension IntelFinding.Kind {
    var title: String {
        switch self {
        case .app: "Intel-only apps"
        case .insideApp: "Intel programs inside apps"
        case .plugin: "Plug-ins"
        case .driver: "Drivers"
        case .backgroundItem: "Background items"
        case .commandLineTool: "Command-line tools"
        case .javaRuntime: "Java runtimes"
        }
    }

    var symbol: String {
        switch self {
        case .app: "app.dashed"
        case .insideApp: "app.badge"
        case .plugin: "puzzlepiece.extension"
        case .driver: "cable.connector"
        case .backgroundItem: "gearshape.2"
        case .commandLineTool: "terminal"
        case .javaRuntime: "cup.and.saucer"
        }
    }

    func explanation(onAppleSilicon: Bool) -> String {
        let note = onAppleSilicon ? "These run through Rosetta." : "These run natively on this Intel Mac."
        switch self {
        case .app: return "Apps built for Intel only. \(note) Look for an Apple silicon version."
        case .insideApp: return "Helpers, updaters and extensions inside apps that are Intel-only. \(note)"
        case .plugin: return "Plug-ins that contain only Intel code. An app that loads them may need to run under Rosetta."
        case .driver: return "Drivers with Intel code only. Drivers cannot run under Rosetta, so they may stop working."
        case .backgroundItem: return "Login items and background jobs that run Intel programs. \(note)"
        case .commandLineTool: return "Terminal programs for Intel, often from an old Homebrew in /usr/local. \(note)"
        case .javaRuntime: return "Java runtimes for Intel. \(note)"
        }
    }
}
