// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Peel's ExclusionsStore (https://github.com/TuguiDragos/Peel), GPL-3.0-or-later.
import Foundation
import Observation
import PeelCore

/// What the user told Warren to leave alone. One list for every tool: Uninstaller, Orphans, Intel, Receipts, Cleanup
/// and Storage all go through the removal engine, which refuses an excluded path, anything inside it and any folder
/// that holds one. Warren starts with the list unread, and the engine moves nothing until it has been read.
@MainActor
@Observable
final class ExclusionsLibrary {
    private(set) var exclusions = Exclusions.notYetRead
    /// The last change could not be written, so it will not be there after a relaunch.
    private(set) var couldNotSave = false
    private(set) var whyNotSaved: FileProblem?
    /// Called whenever the list changes, so the removal engine judges by the current list.
    @ObservationIgnored var onChange: ((Exclusions) -> Void)?

    @ObservationIgnored private let store: ExclusionStore
    /// Changes that could not be written. They stay in force until Warren quits and are laid over the list each time
    /// it is read, so the person is never less protected than they asked.
    @ObservationIgnored private var unsaved: [@Sendable (inout Exclusions) -> Void] = []
    /// The last read or change, which the next one waits for, so they land in the order they were made.
    @ObservationIgnored private var last: Task<Void, Never>?

    init(store: ExclusionStore = ExclusionStore()) {
        self.store = store
    }

    var file: URL { store.url }

    var hasLoaded: Bool { exclusions.hasBeenRead }

    var paths: [URL] {
        exclusions.paths.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }

    var appIdentifiers: [String] {
        exclusions.bundleIdentifiers.sorted()
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        await inTurn { [self] in show(withUnsaved(await store.load())) }
    }

    func add(paths: [URL]) async {
        await change { $0.add(paths) }
    }

    func add(bundleIdentifier: String) async {
        await change { $0.bundleIdentifiers.insert(bundleIdentifier) }
    }

    func remove(paths: [URL]) async {
        await change { $0.remove(paths) }
    }

    func remove(bundleIdentifiers: [String]) async {
        await change { $0.bundleIdentifiers.subtract(bundleIdentifiers) }
    }

    /// Replaces a list that could not be read, which the store keeps under another name, and reads the list again.
    @discardableResult
    func startOver() async -> StartOver {
        await inTurn { [self] in
            let answer = await store.startOver()
            if answer == .started {
                unsaved = []
                couldNotSave = false
                whyNotSaved = nil
            }
            show(withUnsaved(await store.load()))
            return answer
        }
    }

    private func change(_ transform: @escaping @Sendable (inout Exclusions) -> Void) async {
        await inTurn { [self] in
            let changes = unsaved + [transform]
            switch await store.change(startingOverIfUnreadable: true, { list in changes.forEach { $0(&list) } }) {
            case .saved(let saved):
                unsaved = []
                couldNotSave = false
                whyNotSaved = nil
                show(saved)
            case .notSaved(let changed, let why):
                unsaved.append(transform)
                couldNotSave = true
                whyNotSaved = why
                show(changed)
            case .unreadable(let why):
                show(.unreadable(because: why))
            }
        }
    }

    private func inTurn<Answer: Sendable>(_ operation: @escaping () async -> Answer) async -> Answer {
        let previous = last
        let current = Task {
            await previous?.value
            return await operation()
        }
        last = Task { _ = await current.value }
        return await current.value
    }

    private func withUnsaved(_ list: Exclusions) -> Exclusions {
        guard !unsaved.isEmpty else { return list }
        var changed = list.isUnreadable ? .none : list
        unsaved.forEach { $0(&changed) }
        return changed
    }

    private func show(_ list: Exclusions) {
        guard list != exclusions else { return }
        exclusions = list
        onChange?(list)
    }
}
