// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import Observation
import PeelCore

/// Orphaned files (what apps left behind after they were removed), found by the engine ported from Peel. Each group
/// carries a confidence level and the reasons behind it; nothing is ever selected for you.
@MainActor
@Observable
final class OrphanLibrary {
    private(set) var scan: OrphanScan?
    private(set) var isScanning = false
    private(set) var isRemoving = false
    var selection: Set<URL> = []
    var search = ""
    var resultMessage: String?
    var errorMessage: String?

    /// Run after files moved, so other parts of Warren can refresh.
    var onRemoved: ( () async -> Void)?

    private let apps: AppLibrary
    private let removal: RemovalService

    init(apps: AppLibrary, removal: RemovalService) {
        self.apps = apps
        self.removal = removal
    }

    private var canUseAdministrator: Bool { AdministratorRights.current == .askEachTime }

    // MARK: Scanning

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        if apps.apps.isEmpty { await apps.rescan() }
        let installed = apps.apps

        let remembered = await AppMemory().remember(installed)
        let result = await OrphanScanner().scan(installedApps: installed, remembered: remembered)
        await AppMemory().remember(result.appsOnOtherDisks)

        scan = result
        let known = Set(result.groups.flatMap(\.items).map(\.url))
        selection = selection.intersection(known)
        isScanning = false
    }

    // MARK: Derived

    var groups: [OrphanGroup] {
        guard let scan else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scan.groups }
        return scan.groups.filter { group in
            group.title.localizedCaseInsensitiveContains(query)
                || group.items.contains { $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Sum of what could be moved now (items a checkbox can select), for Smart Care and the header.
    var movableBytes: UInt64 {
        guard let scan else { return 0 }
        return scan.groups.reduce(into: UInt64(0)) {
            $0 += UInt64(max(0, $1.movable(canUseHelper: canUseAdministrator).known))
        }
    }

    var selectedItems: [OrphanItem] {
        (scan?.groups ?? []).flatMap(\.items).filter { selection.contains($0.url) }
    }

    var selectedPrivilegedURLs: [URL] {
        selectedItems.filter(\.requiresPrivileges).map(\.url).sorted { $0.path < $1.path }
    }

    var selectedSize: SizeTotal {
        SizeTotal(selectedItems.map(\.size))
    }

    // MARK: Selection

    func canSelect(_ item: OrphanItem, in group: OrphanGroup) -> Bool {
        group.selectableRows(canUseHelper: canUseAdministrator).selectable.contains(item.url)
    }

    func toggle(_ item: OrphanItem, in group: OrphanGroup) {
        guard canSelect(item, in: group) else { return }
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    func selectAll(in group: OrphanGroup) {
        selection = group.selectableRows(canUseHelper: canUseAdministrator).selectingAll(in: selection)
    }

    func selectRecommended(in group: OrphanGroup) {
        selection = group.selectableRows(canUseHelper: canUseAdministrator).selectingRecommended(in: selection)
    }

    func deselect(group: OrphanGroup) {
        selection = group.selectableRows(canUseHelper: canUseAdministrator).deselectingAll(in: selection)
    }

    func clearSelection() { selection = [] }

    // MARK: Removing

    func removeSelection() async {
        let items = selectedItems
        guard !items.isEmpty, !isRemoving else { return }

        isRemoving = true
        resultMessage = nil
        errorMessage = nil

        let installed = apps.apps
        let remembered = await AppMemory().load()
        let scanner = OrphanScanner()
        let own = items.filter { !$0.requiresPrivileges }
        let privileged = items.filter(\.requiresPrivileges)

        var moved = 0
        var lines: [String] = []

        if !own.isEmpty {
            let result = await OrphanRemoval.trash(
                own, installedApps: installed, remembered: remembered, scanner: scanner,
                using: removal.engine, mayUseHelper: false
            )
            await removal.record(result, source: "Orphaned files", tool: "orphans", sizes: Dictionary(own.compactMap { item in item.size.map { (item.url, $0) } }) { first, _ in first })
            moved += result.trashed.count
            lines += result.failures.prefix(5).map { "\($0.url.lastPathComponent): \(RemovalFailureText.describe($0.reason))" }
        }

        if !privileged.isEmpty, canUseAdministrator {
            // Checked again against the installed apps, as for the rest, before the approved batch moves.
            let still = await scanner.stillOrphaned(privileged, installedApps: installed, remembered: remembered)
            let outcome = await AdministratorRemoval.moveToTrash(still.map(\.url), engine: removal.engine)
            moved += outcome.moved.count
            lines += outcome.failures.prefix(4).map { "\($0.url.lastPathComponent): \($0.reason)" }
            if outcome.cancelled { lines.append("Administrator approval was cancelled, so system-owned items stayed.") }
        }

        if moved > 0 {
            resultMessage = "Moved \(moved) item\(moved == 1 ? "" : "s") to the Trash. You can put them back from the Trash."
        }
        if !lines.isEmpty { errorMessage = lines.joined(separator: "\n") }

        selection = []
        isRemoving = false
        await onRemoved?()
        isScanning = false
        await rescan()
    }
}

/// Plain-English text for why the engine rates a group of orphaned files the way it does.
enum OrphanText {
    static func level(_ level: OrphanConfidence.Level) -> String {
        switch level {
        case .certain: "Certain"
        case .likely: "Likely"
        case .unsure: "Unsure"
        }
    }

    static func reason(_ reason: OrphanConfidence.Reason) -> String {
        switch reason {
        case .appLeft(let name, let lastSeen):
            "\(name) was removed (last seen \(lastSeen.formatted(date: .abbreviated, time: .omitted)))."
        case .untouched(let months): "Nothing has written to it for \(months) months."
        case .writtenRecently(let date): "Written on \(date.formatted(date: .abbreviated, time: .omitted)), so something may still use it."
        case .writtenAfterItLeft(let name, _): "Written after \(name) left, so something else may use it."
        case .sameMakerStillInstalled: "Another app by the same developer is still installed."
        case .running(let name): "\(name) is running now."
        case .leadsIntoAnAppThatIsGone: "A link into an app that is gone."
        case .onlyTheName(let name): "Only the name suggests it belonged to \(name)."
        case .nothingClaimsIt: "No installed app claims it."
        case .installedForAnAppThatIsGone(let name): "Installed for \(name), which is gone."
        case .startsAProgramThatIsGone: "Starts a program that no longer exists."
        case .loadedByOtherApps: "Other apps load it (a plug-in), so it is held back."
        }
    }
}
