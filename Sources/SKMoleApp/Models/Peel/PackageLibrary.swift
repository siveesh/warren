// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import PeelCore

/// The installer packages macOS has receipts for, and what each one put on disk. Receipts only record what a
/// package installed; Warren can move a package's leftover files to the Trash and forget the receipt (its records
/// move to the Trash too).
@MainActor
@Observable
final class PackageLibrary {
    private(set) var receipts: [PackageReceipt]?
    private(set) var couldNotAsk = false
    private(set) var isScanning = false
    private(set) var isWorking = false
    var selectedID: String?
    var selection: Set<URL> = []
    var search = ""
    var resultMessage: String?
    var errorMessage: String?

    private let removal: RemovalService

    init(removal: RemovalService) {
        self.removal = removal
    }

    private var canUseAdministrator: Bool { AdministratorRights.current == .askEachTime }

    var selectedReceipt: PackageReceipt? {
        receipts?.first { $0.id == selectedID }
    }

    var filtered: [PackageReceipt] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (receipts ?? []).filter { query.isEmpty || $0.matches(query) }
    }

    func refreshIfNeeded() async {
        if receipts == nil { await refresh() }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        let scan = await PackageReceipts.list()
        receipts = scan.receipts
        couldNotAsk = scan.couldNotAsk
        if let selectedID, !scan.receipts.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
            selection = []
        }
        isScanning = false
    }

    func select(_ receipt: PackageReceipt) {
        selectedID = receipt.id
        selection = []
        resultMessage = nil
        errorMessage = nil
    }

    // MARK: Selection

    private func rows(_ receipt: PackageReceipt) -> SelectableRows<URL> {
        receipt.selectableRows(canUseHelper: canUseAdministrator)
    }

    func canSelect(_ item: PackageReceipt.Item, in receipt: PackageReceipt) -> Bool {
        rows(receipt).selectable.contains(item.url)
    }

    func toggle(_ item: PackageReceipt.Item, in receipt: PackageReceipt) {
        guard canSelect(item, in: receipt) else { return }
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    func selectRecommended(in receipt: PackageReceipt) { selection = rows(receipt).selectingRecommended(in: selection) }
    func selectAll(in receipt: PackageReceipt) { selection = rows(receipt).selectingAll(in: selection) }
    func selectNone(in receipt: PackageReceipt) { selection = rows(receipt).deselectingAll(in: selection) }

    var selectedItems: [PackageReceipt.Item] {
        selectedReceipt?.items.filter { selection.contains($0.url) } ?? []
    }

    var selectedPrivilegedURLs: [URL] {
        selectedItems.filter(\.requiresPrivileges).map(\.url).sorted { $0.path < $1.path }
    }

    var selectedSize: SizeTotal { SizeTotal(selectedItems.map(\.size)) }

    // MARK: Moving files

    func removeSelectedItems() async {
        guard !selectedItems.isEmpty, !isWorking else { return }
        isWorking = true
        resultMessage = nil
        errorMessage = nil

        let items = selectedItems
        let own = items.filter { !$0.requiresPrivileges }.map(\.url)
        let privileged = items.filter(\.requiresPrivileges).map(\.url)

        var moved = 0
        var lines: [String] = []

        if !own.isEmpty {
            let result = await removal.engine.trash(own, usingHelperFor: [])
            moved += result.trashed.count
            lines += result.failures.prefix(5).map { "\($0.url.lastPathComponent): \(RemovalFailureText.describe($0.reason))" }
        }

        if !privileged.isEmpty, canUseAdministrator {
            let outcome = await AdministratorRemoval.moveToTrash(privileged, engine: removal.engine)
            moved += outcome.moved.count
            lines += outcome.failures.prefix(4).map { "\($0.url.lastPathComponent): \($0.reason)" }
            if outcome.cancelled { lines.append("Administrator approval was cancelled, so system-owned items stayed.") }
        }

        report(moved: moved, lines: lines, what: "item")
        selection = []
        isWorking = false
        isScanning = false
        await refresh()
    }

    // MARK: Forgetting receipts

    /// Whether forgetting `receipt` touches system files, which needs administrator rights.
    func forgettingNeedsAdministrator(_ receipt: PackageReceipt) -> Bool {
        PackageActions.forgettingNeedsTheHelper(receipt)
    }

    func forget(_ receipt: PackageReceipt) async {
        guard !isWorking else { return }
        isWorking = true
        resultMessage = nil
        errorMessage = nil

        var moved = 0
        var lines: [String] = []

        if forgettingNeedsAdministrator(receipt) {
            if canUseAdministrator {
                let folder = receipt.volume.appendingPathComponent("private/var/db/receipts", isDirectory: true)
                let files = ["bom", "plist"]
                    .map { folder.appendingPathComponent("\(receipt.identifier).\($0)") }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                let outcome = await AdministratorRemoval.moveToTrash(files, engine: removal.engine)
                moved += outcome.moved.count
                lines += outcome.failures.prefix(4).map { "\($0.url.lastPathComponent): \($0.reason)" }
                if outcome.cancelled { lines.append("Administrator approval was cancelled.") }
            } else {
                lines.append("Forgetting this receipt needs administrator rights, which are turned off in Settings.")
            }
        } else {
            let result = await PackageActions.forget(receipt)
            moved += result.trashed.count
            lines += result.failures.prefix(4).map { "\($0.url.lastPathComponent): \(RemovalFailureText.describe($0.reason))" }
        }

        report(moved: moved, lines: lines, what: "receipt file")
        isWorking = false
        isScanning = false
        await refresh()
    }

    private func report(moved: Int, lines: [String], what: String) {
        if moved > 0 {
            resultMessage = "Moved \(moved) \(what)\(moved == 1 ? "" : "s") to the Trash. You can put them back from the Trash."
        }
        if !lines.isEmpty { errorMessage = lines.joined(separator: "\n") }
    }
}
