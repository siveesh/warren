import Foundation
import Observation
import RelayCore

/// Observable, persisted library of workflow tasks.
@MainActor
@Observable
public final class TaskLibraryModel {

    public private(set) var tasks: [RelayTask] = []

    public let store: any TaskStoring

    public init(store: any TaskStoring) {
        self.store = store
    }

    public func load() async {
        do {
            var loaded = try await store.loadTasks()
            if loaded.isEmpty {
                loaded = RelayTask.samples
                try? await store.save(loaded)
            }
            tasks = loaded
        } catch {
            tasks = RelayTask.samples
        }
    }

    public func add(_ task: RelayTask) { tasks.append(task); persist() }

    public func update(_ task: RelayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        persist()
    }

    public func delete(_ task: RelayTask) {
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    private func persist() {
        let snapshot = tasks
        Task { try? await store.save(snapshot) }
    }
}
