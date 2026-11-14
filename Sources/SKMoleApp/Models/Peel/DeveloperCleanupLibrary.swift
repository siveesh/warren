// SPDX-License-Identifier: GPL-3.0-or-later
// Built on Peel's developer engine (DeveloperCaches, ProjectArtifacts), GPL-3.0-or-later, with the simulator runtime
// handling from the author's Xcode Cleaner.
import AppKit
import Foundation
import Observation
import PeelCore

/// One project folder and everything a build left inside it.
struct ProjectGroup: Identifiable, Hashable {
    let project: URL
    let name: String
    let artifacts: [ProjectArtifact]

    var id: URL { project }
    var total: SizeTotal { SizeTotal(artifacts.map(\.size)) }
}

/// Developer files that tools make again: Xcode DerivedData (one row per workspace), archives (one per `.xcarchive`),
/// Device Support folders (one per system version and build), simulator runtimes, package caches, and build folders
/// inside the user's projects. Nothing is selected for the user except what the engine itself recommends when they ask.
@MainActor
@Observable
final class DeveloperCleanupLibrary {
    enum Pane: String, CaseIterable, Identifiable {
        case tools = "Xcode & Tools"
        case simulators = "Simulators"
        case projects = "Projects"

        var id: String { rawValue }
    }

    var pane: Pane = .tools

    // Xcode and tool folders
    private(set) var environments: [DeveloperEnvironment]?
    private(set) var isScanning = false
    /// Selected folders, in tools and in projects.
    var selected: Set<URL> = []
    private(set) var isRemoving = false
    private(set) var resultMessage: String?
    private(set) var errorMessage: String?

    // Simulators
    private(set) var runtimes: [SimulatorRuntime]?
    private(set) var isLoadingRuntimes = false
    var selectedRuntimes: Set<String> = []
    private(set) var simulatorMessage: String?
    private(set) var isChangingSimulators = false

    // Projects
    private(set) var projectGroups: [ProjectGroup]?
    private(set) var projectFolders: [URL]
    private(set) var isScanningProjects = false
    private(set) var projectNotes: [String] = []

    var onRemoved: (@MainActor () async -> Void)?

    private let removal: RemovalService
    private let exclusionsLibrary: ExclusionsLibrary
    private let defaults: UserDefaults
    private static let foldersKey = "developerCleanup.projectFolders"

    /// The kinds of folder this page lists. Model weights, editor state for old projects and installed environments are
    /// left out: they are not cheap to make again, and Warren keeps local AI models off limits anyway.
    static let shownKinds: Set<DeveloperEnvironment.ContentKind> = [.buildData, .downloads, .cache, .logs, .deviceSupport, .archives]

    init(removal: RemovalService, exclusions: ExclusionsLibrary, defaults: UserDefaults = .standard) {
        self.removal = removal
        self.exclusionsLibrary = exclusions
        self.defaults = defaults
        projectFolders = (defaults.array(forKey: Self.foldersKey) as? [String] ?? [])
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    // MARK: Tools

    /// What the environment lists here. Homebrew's own folders belong to the Homebrew page.
    func locations(of environment: DeveloperEnvironment) -> [DeveloperEnvironment.Location] {
        environment.locations.filter { Self.shownKinds.contains($0.kind) && !removalScope.isHomebrewManaged($0.url) }
    }

    private let removalScope = RemovalScope()

    var shownEnvironments: [DeveloperEnvironment] {
        (environments ?? [])
            .filter { !locations(of: $0).isEmpty }
            .sorted { SizeTotal(locations(of: $0).map(\.size)) > SizeTotal(locations(of: $1).map(\.size)) }
    }

    func rescanTools() async {
        guard !isScanning else { return }
        isScanning = true
        await exclusionsLibrary.loadIfNeeded()
        let found = await DeveloperCaches.scan(exclusions: removal.exclusions)
        environments = found
        let known = Set(found.flatMap(\.locations).map(\.url)).union(projectGroups?.flatMap(\.artifacts).map(\.url) ?? [])
        selected.formIntersection(known)
        isScanning = false
    }

    func loadIfNeeded() async {
        if environments == nil { await rescanTools() }
    }

    func runningApp(for environment: DeveloperEnvironment) -> String? {
        environment.runningApp
    }

    func isSelected(_ url: URL) -> Bool { selected.contains(url) }

    func toggle(_ url: URL) {
        if !selected.insert(url).inserted { selected.remove(url) }
    }

    func selectRecommended(in environment: DeveloperEnvironment) {
        selected.formUnion(locations(of: environment).filter(\.isRecommended).map(\.url))
    }

    func deselectAll(in environment: DeveloperEnvironment) {
        selected.subtract(environment.locations.map(\.url))
    }

    /// Selects the rows of `kind` last written more than `days` ago. A row whose date is unknown is left alone.
    func selectOlder(than days: Int, kind: DeveloperEnvironment.ContentKind?, in environment: DeveloperEnvironment) {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        selected.formUnion(
            locations(of: environment)
                .filter { (kind == nil || $0.kind == kind) && $0.heldBack == nil }
                .filter { location in location.lastWritten.map { $0 < cutoff } ?? false }
                .map(\.url)
        )
    }

    /// Keeps the newest `count` rows of `kind` and selects every older one. Rows of unknown date are never selected.
    func keepNewest(_ count: Int, kind: DeveloperEnvironment.ContentKind, in environment: DeveloperEnvironment) {
        let dated = locations(of: environment)
            .filter { $0.kind == kind && $0.heldBack == nil }
            .compactMap { location in location.lastWritten.map { (location, $0) } }
            .sorted { $0.1 > $1.1 }
        selected.formUnion(dated.dropFirst(max(0, count)).map { $0.0.url })
    }

    // MARK: Projects

    func rescanProjects() async {
        guard !isScanningProjects else { return }
        isScanningProjects = true
        await exclusionsLibrary.loadIfNeeded()
        let scan = await ProjectArtifacts.scan(roots: projectFolders, exclusions: removal.exclusions)
        let byProject = Array(Dictionary(grouping: scan.artifacts, by: \.project))
        let names = ProjectArtifacts.names(of: byProject.map(\.key))
        projectGroups = zip(byProject, names)
            .map { entry, name in
                ProjectGroup(
                    project: entry.key, name: name,
                    artifacts: entry.value.sorted { SizeTotal([$0.size]) > SizeTotal([$1.size]) }
                )
            }
            .sorted { $0.total > $1.total }
        var notes: [String] = []
        if scan.wasCutShort { notes.append("The scan reached its limit, so the list may be incomplete.") }
        if scan.needsFullDiskAccess { notes.append("Some folders could not be read. Grant Warren Full Disk Access to see them.") }
        if !scan.unreadableLocations.isEmpty { notes.append("\(scan.unreadableLocations.count) folder(s) could not be read, so what they hold isn't known.") }
        projectNotes = notes
        selected.formIntersection(Set(environments?.flatMap(\.locations).map(\.url) ?? []).union(scan.artifacts.map(\.url)))
        isScanningProjects = false
    }

    func loadProjectsIfNeeded() async {
        if projectGroups == nil { await rescanProjects() }
    }

    func chooseProjectFolders() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose the folders your projects live in."
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.filter { url in !projectFolders.contains { $0.standardizedFileURL == url.standardizedFileURL } }
        let reasons = await ProjectArtifacts.refusals(of: chosen, besides: projectFolders)
        let keeping = zip(chosen, reasons).filter { $0.1 == nil }.map(\.0)
        projectNotes = zip(chosen, reasons).compactMap { url, reason in
            reason.map { _ in "\(url.lastPathComponent) can't be searched for build folders." }
        }
        guard !keeping.isEmpty else { return }
        projectFolders += keeping
        saveFolders()
        await rescanProjects()
    }

    func removeProjectFolder(_ url: URL) async {
        projectFolders.removeAll { $0 == url }
        saveFolders()
        await rescanProjects()
    }

    private func saveFolders() {
        defaults.set(projectFolders.map { $0.path(percentEncoded: false) }, forKey: Self.foldersKey)
    }

    // MARK: Selection and removal

    var selectedSize: SizeTotal {
        var sizes: [URL: Int64?] = [:]
        for environment in environments ?? [] {
            for location in environment.locations where selected.contains(location.url) { sizes[location.url] = location.size }
        }
        for artifact in (projectGroups ?? []).flatMap(\.artifacts) where selected.contains(artifact.url) {
            sizes[artifact.url] = artifact.size
        }
        return SizeTotal(movingItemsAt: sizes)
    }

    /// The name of a running app whose folders are selected, which has to quit first.
    var appToQuit: String? {
        for environment in environments ?? [] where environment.locations.contains(where: { selected.contains($0.url) }) {
            if let name = environment.runningApp { return name }
        }
        return nil
    }

    func removeSelection() async {
        guard !isRemoving, !selected.isEmpty else { return }
        if let app = appToQuit {
            errorMessage = "Quit \(app) first: it writes in these folders. Nothing was moved."
            resultMessage = nil
            return
        }
        isRemoving = true
        resultMessage = nil
        errorMessage = nil

        let artifacts = (projectGroups ?? []).flatMap(\.artifacts)
        let artifactURLs = Set(artifacts.map(\.url))
        let toolURLs = selected.subtracting(artifactURLs)
        let chosenArtifacts = artifacts.filter { selected.contains($0.url) }

        var sizes: [URL: Int64] = [:]
        for location in (environments ?? []).flatMap(\.locations) where selected.contains(location.url) {
            if let size = location.size { sizes[location.url] = size }
        }
        for artifact in chosenArtifacts { if let size = artifact.size { sizes[artifact.url] = size } }

        var moved = 0
        var failures: [TrashFailure] = []

        if !toolURLs.isEmpty {
            let result = await removal.engine.trash(Array(toolURLs))
            await removal.record(result, source: "Developer Cleanup", tool: "developer", sizes: sizes)
            moved += result.trashed.count
            failures += result.failures
        }
        if !chosenArtifacts.isEmpty {
            // A project that changed since the scan is refused, as the engine's check reads it as it is now.
            let changed = await ProjectArtifacts.changedSinceScan(chosenArtifacts, among: artifacts)
            let result = await removal.engine.trash(chosenArtifacts.map(\.url), refusing: { changed[$0] })
            await removal.record(result, source: "Developer Cleanup", tool: "developer", sizes: sizes)
            moved += result.trashed.count
            failures += result.failures
        }

        if moved > 0 {
            resultMessage = "Moved \(moved) item\(moved == 1 ? "" : "s") to the Trash. You can put them back from History."
        }
        if let first = failures.first {
            errorMessage = "\(failures.count) item\(failures.count == 1 ? " was" : "s were") not moved: \(RemovalFailureText.describe(first.reason))"
        }
        selected = []
        isRemoving = false
        await rescanTools()
        if projectGroups != nil { await rescanProjects() }
        await onRemoved?()
    }

    // MARK: Simulators

    func loadRuntimes() async {
        guard !isLoadingRuntimes else { return }
        isLoadingRuntimes = true
        runtimes = await SimulatorTools.runtimes()
        selectedRuntimes.formIntersection(Set(runtimes?.map(\.id) ?? []))
        isLoadingRuntimes = false
    }

    func loadRuntimesIfNeeded() async {
        if runtimes == nil { await loadRuntimes() }
    }

    func deleteSelectedRuntimes() async {
        guard !isChangingSimulators, !selectedRuntimes.isEmpty else { return }
        isChangingSimulators = true
        let ids = Array(selectedRuntimes)
        let failures = await SimulatorTools.delete(runtimeIDs: ids)
        selectedRuntimes = []
        simulatorMessage = failures.isEmpty
            ? "Deleted \(ids.count) simulator runtime\(ids.count == 1 ? "" : "s"). Xcode can download them again."
            : "Some runtimes were not deleted: \(failures.joined(separator: " "))"
        isChangingSimulators = false
        await loadRuntimes()
        await rescanTools()
    }

    func deleteUnavailableDevices() async {
        guard !isChangingSimulators else { return }
        isChangingSimulators = true
        if let failure = await SimulatorTools.deleteUnavailableDevices() {
            simulatorMessage = "Unavailable devices were not deleted: \(failure)"
        } else {
            simulatorMessage = "Deleted the simulator devices Xcode reports as unavailable."
        }
        isChangingSimulators = false
        await rescanTools()
    }
}
