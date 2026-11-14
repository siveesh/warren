// SPDX-License-Identifier: GPL-3.0-or-later
// Built on Peel's DuplicateFinder and DuplicateRemoval (https://github.com/TuguiDragos/Peel), GPL-3.0-or-later.
import AppKit
import Foundation
import Observation
import PeelCore

/// Identical folders and identical files in the folders the user chooses. The engine compares names and bytes, never
/// offers the last copy, holds back copies that sync to other devices, and checks each copy again right before it
/// moves. Moves go to the Trash with a way back in History.
@MainActor
@Observable
final class DuplicatesLibrary {
    private(set) var scan: DuplicateScan?
    private(set) var isScanning = false
    private(set) var progress = ""
    private(set) var isRemoving = false
    private(set) var resultMessage: String?
    private(set) var errorMessage: String?
    private(set) var folders: [URL]
    private(set) var refusedFolders: [String] = []
    var selectedFiles: Set<URL> = []
    var selectedFolders: Set<URL> = []
    var minimumSize: Int64 = DuplicateScanOptions.defaultMinimumSize

    var onRemoved: (@MainActor () async -> Void)?

    private let removal: RemovalService
    private let exclusionsLibrary: ExclusionsLibrary
    private let defaults: UserDefaults
    private let profile: @MainActor () -> CleanupSafetyProfile
    @ObservationIgnored private var task: Task<Void, Never>?
    private static let foldersKey = "duplicates.folders"

    init(
        removal: RemovalService,
        exclusions: ExclusionsLibrary,
        defaults: UserDefaults = .standard,
        profile: @escaping @MainActor () -> CleanupSafetyProfile = { .balanced }
    ) {
        self.removal = removal
        self.exclusionsLibrary = exclusions
        self.defaults = defaults
        self.profile = profile
        let saved = defaults.array(forKey: Self.foldersKey) as? [String]
        folders = saved?.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? DuplicateFinder().defaultFolders
    }

    /// The Cautious profile never suggests copies: the person picks every one.
    var canSuggest: Bool { profile() != .cautious }

    var selectedSize: Int64 {
        guard let scan else { return 0 }
        let files = scan.groups.flatMap(\.files).filter { selectedFiles.contains($0.url) }.map(\.reclaimableSize)
        let folders = scan.folderGroups.flatMap(\.folders).filter { selectedFolders.contains($0.url) }.map(\.reclaimableSize)
        return (files + folders).reduce(0) { $0 &+ $1 }
    }

    var selectionCount: Int { selectedFiles.count + selectedFolders.count }

    func start() {
        guard !isScanning else { return }
        task = Task { await run() }
    }

    func stop() { task?.cancel() }

    private func run() async {
        isScanning = true
        resultMessage = nil
        errorMessage = nil
        progress = "Starting…"
        await exclusionsLibrary.loadIfNeeded()
        let finder = DuplicateFinder(exclusions: removal.exclusions, digestMemory: DigestMemory())
        var options = DuplicateScanOptions(folders: folders)
        options.minimumSize = minimumSize
        let callback: @Sendable (DuplicateScanProgress) -> Void = { [weak self] update in
            let text: String = switch update {
            case .listing(let found): "Looking through \(found) folders…"
            case .collecting(let found): "Found \(found) files…"
            case .comparing(let done, let total): "Comparing \(done) of \(total) files…"
            case .verifying(let read, let total): "Verifying \(ByteFormatting.format(UInt64(max(0, read)))) of \(ByteFormatting.format(UInt64(max(0, total))))…"
            }
            Task { @MainActor in self?.progress = text }
        }
        do {
            let result = try await finder.scan(options, progress: callback)
            scan = result
            selectedFiles = []
            selectedFolders = []
        } catch {
            errorMessage = "The scan was stopped."
        }
        isScanning = false
        progress = ""
    }

    // MARK: Folders to search

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to search for duplicates."
        guard panel.runModal() == .OK else { return }
        let finder = DuplicateFinder()
        var refused: [String] = []
        for url in panel.urls where !folders.contains(url) {
            if finder.reasonToSetAside(url) != nil {
                refused.append(url.lastPathComponent)
            } else {
                folders.append(url)
            }
        }
        refusedFolders = refused
        save()
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        save()
    }

    private func save() {
        defaults.set(folders.map { $0.path(percentEncoded: false) }, forKey: Self.foldersKey)
    }

    // MARK: Selection

    func toggle(file url: URL) {
        if !selectedFiles.insert(url).inserted { selectedFiles.remove(url) }
        selectedFiles = scan?.keepingOneOfEach(selectedFiles) ?? selectedFiles
    }

    func toggle(folder url: URL) {
        if !selectedFolders.insert(url).inserted { selectedFolders.remove(url) }
        selectedFolders = scan?.keepingOneOfEachFolder(selectedFolders) ?? selectedFolders
    }

    func selectSuggested() {
        guard canSuggest, let scan else { return }
        selectedFiles = scan.suggestedSelection
        selectedFolders = scan.suggestedFolderSelection
    }

    func clearSelection() {
        selectedFiles = []
        selectedFolders = []
    }

    // MARK: Removal

    func removeSelection() async {
        guard !isRemoving, let scan, selectionCount > 0 else { return }
        isRemoving = true
        resultMessage = nil
        errorMessage = nil
        var sizes: [URL: Int64] = [:]
        for file in scan.groups.flatMap(\.files) where selectedFiles.contains(file.url) { sizes[file.url] = file.reclaimableSize }
        for folder in scan.folderGroups.flatMap(\.folders) where selectedFolders.contains(folder.url) { sizes[folder.url] = folder.reclaimableSize }

        let result = await DuplicateRemoval.trash(selectedFiles, folders: selectedFolders, from: scan, using: removal.engine)
        await removal.record(result, source: "Duplicates", tool: "duplicates", sizes: sizes)
        let moved = result.trashed.count
        if moved > 0 { resultMessage = "Moved \(moved) cop\(moved == 1 ? "y" : "ies") to the Trash. You can put them back from History." }
        if let first = result.failures.first {
            errorMessage = "\(result.failures.count) not moved: \(RemovalFailureText.describe(first.reason))"
        }
        isRemoving = false
        await run()
        await onRemoved?()
    }
}
