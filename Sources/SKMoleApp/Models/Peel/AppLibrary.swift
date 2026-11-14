// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import Observation
import PeelCore

/// The app inventory and the uninstall/reset flow, driven by the engine ported from Peel. Everything it moves goes
/// through `RemovalService`, the one removal engine.
@MainActor
@Observable
final class AppLibrary {
    enum Mode: String, CaseIterable, Identifiable {
        case uninstall = "Uninstall"
        case reset = "Reset"

        var id: String { rawValue }
    }

    // MARK: Inventory

    private(set) var apps: [PeelCore.InstalledApp] = []
    private(set) var scanNote: String?
    private(set) var isScanning = false

    // MARK: Selected app

    private(set) var selectedURL: URL?
    private(set) var uninstallation: Uninstallation?
    private(set) var reset: AppReset?
    private(set) var isPreparing = false
    private(set) var isRemoving = false
    var mode: Mode = .uninstall
    var selection: Set<URL> = []
    var resultMessage: String?
    var errorMessage: String?
    /// Resets the app's privacy permissions too, as the engine offers.
    var resetPrivacy = false

    /// Run after something was removed, so the rest of Warren (inventory, Cleanup, Storage) can refresh.
    var onRemoved: (() async -> Void)?

    private let removal: RemovalService
    var removalEngine: TrashService { removal.engine }
    /// Without the privileged helper (a later round), nothing that needs administrator rights is moved.
    private let canUseHelper = false

    init(removal: RemovalService) {
        self.removal = removal
    }

    var selectedApp: PeelCore.InstalledApp? {
        guard let selectedURL else { return nil }
        return apps.first { $0.url == selectedURL } ?? uninstallation?.app ?? reset?.app
    }

    /// Instances of the selected app that are running now.
    var runningInstances: [NSRunningApplication] {
        guard let identifier = selectedApp?.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { !$0.isTerminated }
    }

    // MARK: Scanning

    @discardableResult
    func rescan() async -> [PeelCore.InstalledApp] {
        isScanning = true
        let scan = await AppCatalog.scan()
        apps = scan.apps
        scanNote = Self.note(for: scan)
        isScanning = false
        return scan.apps
    }

    private static func note(for scan: AppScan) -> String? {
        if scan.needsFullDiskAccess {
            return "Some app folders could not be read. Grant Warren Full Disk Access to list every app."
        }

        if !scan.unreadable.isEmpty {
            return "\(scan.unreadable.count) app location\(scan.unreadable.count == 1 ? "" : "s") could not be read."
        }

        return nil
    }

    // MARK: Selecting and preparing

    func select(url: URL) async {
        selectedURL = url
        resultMessage = nil
        errorMessage = nil
        await prepare()
    }

    func clearSelection() {
        selectedURL = nil
        uninstallation = nil
        reset = nil
        selection = []
    }

    func setMode(_ newMode: Mode) async {
        mode = newMode
        await prepare()
    }

    private func prepare() async {
        guard let url = selectedURL else { return }

        let known = apps.first { $0.url == url }
        guard let app = known ?? AppInspector.inspect(url) else {
            errorMessage = "Warren could not read this app."
            return
        }

        isPreparing = true
        uninstallation = nil
        reset = nil
        selection = []

        let installed = apps
        switch mode {
        case .uninstall:
            let plan = await Uninstallation.prepare(app, installedApps: installed)
            guard selectedURL == url, mode == .uninstall else { return }
            uninstallation = plan
            selection = plan.suggestedSelection(canUseHelper: canUseHelper)
        case .reset:
            let plan = await AppReset.prepare(app, installedApps: installed)
            guard selectedURL == url, mode == .reset else { return }
            reset = plan
            selection = plan.suggestedSelection
        }

        isPreparing = false
    }

    // MARK: Selection helpers

    var recommendedSelection: Set<URL> {
        switch mode {
        case .uninstall: uninstallation?.suggestedSelection(canUseHelper: canUseHelper) ?? []
        case .reset: reset?.suggestedSelection ?? []
        }
    }

    var selectableURLs: Set<URL> {
        switch mode {
        case .uninstall: uninstallation?.selectable(canUseHelper: canUseHelper) ?? []
        case .reset: Set(reset?.items.map(\.url) ?? [])
        }
    }

    func selectRecommended() { selection = recommendedSelection }
    func selectAll() { selection = selectableURLs }
    func selectNone() { selection = [] }

    func toggle(_ url: URL) {
        guard selectableURLs.contains(url) else { return }
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }

    /// Size of what is selected; `isComplete` is false when some size was not measured.
    var selectedSize: SizeTotal {
        switch mode {
        case .uninstall:
            guard let plan = uninstallation else { return SizeTotal(known: 0, isComplete: true) }
            var sizes: [Int64?] = plan.scan.leftovers.filter { selection.contains($0.url) }
                .map { $0.isMeasured ? $0.size : nil }
            if selection.contains(plan.app.url) { sizes.append(plan.isAppMeasured ? plan.appSize : nil) }
            return SizeTotal(sizes)
        case .reset:
            return reset?.size(of: selection) ?? SizeTotal(known: 0, isComplete: true)
        }
    }

    // MARK: Removing

    /// Quits the app if it is running, waiting a few seconds. Returns false when it would not quit.
    private func quitSelectedApp() async -> Bool {
        let instances = runningInstances
        guard !instances.isEmpty else { return true }

        instances.forEach { $0.terminate() }
        for _ in 0..<40 {
            if runningInstances.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }

        return runningInstances.isEmpty
    }

    func removeSelection() async {
        guard let app = selectedApp, !selection.isEmpty, !isRemoving else { return }

        isRemoving = true
        resultMessage = nil
        errorMessage = nil

        guard await quitSelectedApp() else {
            errorMessage = "\(app.name) did not quit. Quit it yourself and try again."
            isRemoving = false
            return
        }

        switch mode {
        case .uninstall:
            guard let plan = uninstallation else { break }
            let result = await plan.move(selection, using: removal.engine, throughTheHelper: false)
            report(result, appName: app.name)
        case .reset:
            guard let plan = reset else { break }
            let outcome = await plan.run(selection, resettingPrivacy: resetPrivacy, exclusions: .none, isOpen: { false })
            report(outcome.result, appName: app.name, stop: outcome.stop.map { "\($0)" })
        }

        isRemoving = false
        await onRemoved?()
        await rescan()
        if apps.contains(where: { $0.url == app.url }) || mode == .reset {
            await prepare()
        } else {
            clearSelection()
        }
    }

    private func report(_ result: TrashResult, appName: String, stop: String? = nil) {
        let moved = result.trashed.count
        if let stop {
            errorMessage = "Nothing was changed for \(appName): \(LeftoverText.humanize(stop))."
            return
        }

        if !result.failures.isEmpty {
            let lines = result.failures.prefix(5).map {
                "\($0.url.lastPathComponent): \(RemovalFailureText.describe($0.reason))"
            }
            errorMessage = "\(result.failures.count) item\(result.failures.count == 1 ? "" : "s") stayed.\n" + lines.joined(separator: "\n")
        }

        if moved > 0 {
            resultMessage = "Moved \(moved) item\(moved == 1 ? "" : "s") to the Trash. You can put them back from the Trash."
        }
    }
}

extension AppLibrary {
    /// Whether `app` sits in a Trash folder.
    func isInTrash(_ app: PeelCore.InstalledApp) -> Bool {
        TrashService.isInsideATrash(app.url)
    }

    /// Uninstalls several apps with what the engine recommends for each. Anything that needs review stays.
    func removeMany(_ urls: [URL]) async {
        guard !isRemoving else { return }
        isRemoving = true
        resultMessage = nil
        errorMessage = nil

        var movedItems = 0
        var failures: [String] = []

        for url in urls {
            let known = apps.first { $0.url == url }
            guard let app = known ?? AppInspector.inspect(url) else { continue }

            for instance in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier ?? "") {
                instance.terminate()
            }

            let plan = await Uninstallation.prepare(app, installedApps: apps)
            let selection = plan.suggestedSelection(canUseHelper: false)
            guard !selection.isEmpty else {
                failures.append("\(app.name): nothing could be removed.")
                continue
            }

            let result = await plan.move(selection, using: removalEngine, throughTheHelper: false)
            movedItems += result.trashed.count
            for failure in result.failures {
                failures.append("\(app.name) - \(failure.url.lastPathComponent): \(RemovalFailureText.describe(failure.reason))")
            }
        }

        isRemoving = false
        if movedItems > 0 { resultMessage = "Moved \(movedItems) items to the Trash." }
        if !failures.isEmpty { errorMessage = failures.prefix(6).joined(separator: "\n") }
        clearSelection()
        await onRemoved?()
        await rescan()
    }
}

extension AppLibrary {
    /// Apps sitting in the user's Trash, for the leftover review of apps that were dragged there.
    nonisolated static func discoverTrashedApplications() -> [InstalledApp] {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let entries = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.pathExtension.lowercased() == "app" }
            .compactMap { AppInspector.inspect($0) }
            .map { InstalledApp(peel: $0, location: .trash) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
