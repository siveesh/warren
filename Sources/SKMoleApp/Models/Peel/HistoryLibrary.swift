// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import PeelCore

/// Everything Warren moved to the Trash (Cleanup, Uninstaller, Orphans, Packages, Storage) with a way back, and
/// the removals the guard refused. The engine writes each move down before it happens, so a removal cut short
/// still appears here.
@MainActor
@Observable
final class HistoryLibrary {
    enum Tab: String, CaseIterable, Identifiable {
        case removals = "Removals"
        case refusals = "Refused"

        var id: String { rawValue }
    }

    var tab: Tab = .removals
    private(set) var records: [RemovalRecord] = []
    private(set) var refusals: [RefusalRecord] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var logProblem: String?
    var selection: Set<UUID> = []
    var search = ""
    var message: String?
    var errorMessage: String?

    /// Run after items went back, so Cleanup, Storage and the app inventory refresh.
    var onRestored: (@MainActor () async -> Void)?

    private let log = RemovalLog()
    private let refusalLog = RefusalLog()
    private let removal: RemovalService

    init(removal: RemovalService) {
        self.removal = removal
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true

        let outcome = await log.load()
        records = (outcome.records ?? []).sorted { $0.date > $1.date }
        logProblem = outcome.problem.map { "Warren could not read its removal history (\(String(describing: $0)))." }
        selection = selection.intersection(Set(records.map(\.id)))

        let refused = await refusalLog.load()
        refusals = (refused.records ?? []).sorted { $0.date > $1.date }

        isLoading = false
    }

    // MARK: Derived

    var filtered: [RemovalRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter {
            $0.originalURL.lastPathComponent.localizedCaseInsensitiveContains(query)
                || $0.originalURL.path.localizedCaseInsensitiveContains(query)
                || $0.source.localizedCaseInsensitiveContains(query)
        }
    }

    /// Removals grouped by the batch that moved them together, newest batch first.
    var batches: [(id: UUID, date: Date, records: [RemovalRecord])] {
        Dictionary(grouping: filtered, by: \.batch)
            .map { (id: $0.key, date: $0.value.map(\.date).max() ?? .distantPast, records: $0.value.sorted { $0.originalURL.path < $1.originalURL.path }) }
            .sorted { $0.date > $1.date }
    }

    func canPutBack(_ record: RemovalRecord) -> Bool {
        record.isStillInTrash
    }

    var selectedRecords: [RemovalRecord] {
        records.filter { selection.contains($0.id) }
    }

    func toggle(_ record: RemovalRecord) {
        guard canPutBack(record) else { return }
        if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) }
    }

    func select(batch records: [RemovalRecord]) {
        selection.formUnion(records.filter(canPutBack).map(\.id))
    }

    func clearSelection() { selection = [] }

    // MARK: Put back

    func putBackSelection() async {
        await putBack(selectedRecords)
    }

    func putBack(batch records: [RemovalRecord]) async {
        await putBack(records.filter(canPutBack))
    }

    /// Puts the newest batch back.
    func undoLastRemoval() async {
        guard let latest = batches.first else { return }
        await putBack(batch: latest.records)
    }

    func putBack(_ chosen: [RemovalRecord]) async {
        let ordered = chosen.inPutBackOrder
        guard !ordered.isEmpty, !isWorking else { return }

        isWorking = true
        message = nil
        errorMessage = nil

        let result = await removal.engine.restore(ordered.map(\.trashedItem), canUseHelper: false)

        var back: Set<UUID> = []
        var problems: [String] = []
        for (record, failure) in zip(ordered, result.failures) {
            if let failure {
                problems.append("\(record.originalURL.lastPathComponent): \(Self.describe(failure))")
            } else {
                back.insert(record.id)
            }
        }

        if !back.isEmpty {
            _ = await log.remove(back)
            message = "Put back \(back.count) item\(back.count == 1 ? "" : "s") where \(back.count == 1 ? "it" : "they") came from."
        }
        if !problems.isEmpty { errorMessage = problems.prefix(6).joined(separator: "\n") }

        selection.subtract(back)
        isWorking = false
        isLoading = false
        await load()
        if !back.isEmpty { await onRestored?() }
    }

    /// Removes records from the list. What is in the Trash stays there.
    func forget(_ chosen: [RemovalRecord]) async {
        guard !chosen.isEmpty else { return }
        _ = await log.remove(Set(chosen.map(\.id)))
        selection.subtract(chosen.map(\.id))
        isLoading = false
        await load()
    }

    static func describe(_ failure: RestoreFailure) -> String {
        switch failure {
        case .missingFromTrash: "It is no longer in the Trash."
        case .alreadyThere: "Something is already at its old place."
        case .needsHelper: "Putting it back needs administrator rights."
        case .notAllowed(let refusal): RemovalFailureText.describe(refusal)
        case .notAllowedByTheHelper(let text): text
        case .notInATrash: "The record does not point into a Trash."
        case .locked, .folderLocked: "It is locked. Unlock it in Finder first."
        case .folderGone: "The folder it came from is gone."
        case .needsAppManagement: "macOS needs App Management for Warren to put this app back."
        case .notPermitted: "macOS did not allow this change."
        case .failed(let text): text
        case .replacementStays: "Something newer stands in its place."
        }
    }
}
