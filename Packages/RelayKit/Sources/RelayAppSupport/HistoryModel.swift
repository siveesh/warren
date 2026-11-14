import Foundation
import Observation
import RelayCore

/// Observable, persisted execution-history log.
@MainActor
@Observable
public final class HistoryModel {

    public private(set) var records: [ExecutionRecord] = []

    private let store: any HistoryStoring

    public init(store: any HistoryStoring) {
        self.store = store
    }

    public func load() async {
        records = (try? await store.load()) ?? []
    }

    /// Appends a record (most recent last) and persists.
    public func append(_ record: ExecutionRecord) {
        records.append(record)
        persist()
    }

    public func clear() {
        records.removeAll()
        persist()
    }

    /// Records most-recent first, for display.
    public var newestFirst: [ExecutionRecord] {
        records.reversed()
    }

    private func persist() {
        let snapshot = records
        Task { try? await store.save(snapshot) }
    }
}
