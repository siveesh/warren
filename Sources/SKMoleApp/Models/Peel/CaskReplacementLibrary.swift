// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import Observation
import PeelCore

/// Apps installed by hand that Homebrew has a cask for. Each can be handed to Homebrew where it is (adopt: the app
/// and its settings stay, Homebrew only manages it from then on) or replaced by Homebrew's own copy (the current
/// copy goes to the Trash first, so History can put it back).
@MainActor
@Observable
final class CaskReplacementLibrary {
    struct Candidate: Identifiable, Hashable {
        let app: PeelCore.InstalledApp
        let cask: HomebrewPackage

        var id: URL { app.url }
        var hasOwnUpdater: Bool { cask.appUpdatesItself }
    }

    enum Action {
        case adopt
        case replace

        var title: String {
            switch self {
            case .adopt: "Hand to Homebrew"
            case .replace: "Replace with Homebrew’s copy"
            }
        }
    }

    private(set) var candidates: [Candidate] = []
    private(set) var alreadyManaged = 0
    private(set) var fromAppStore = 0
    private(set) var hasScanned = false
    private(set) var isScanning = false
    private(set) var workingOn: URL?
    private(set) var transcript = ""
    var resultMessage: String?
    var errorMessage: String?
    var selection: Set<URL> = []

    private let removal: RemovalService

    init(removal: RemovalService) {
        self.removal = removal
    }

    /// Apps worth asking Homebrew about: put there by hand, not from the App Store, not Apple's, not Warren itself.
    static func isEligible(_ app: PeelCore.InstalledApp) -> Bool {
        guard !app.isFromAppStore, !app.isSignedByTheAppStore, !app.isSystemProtected, !app.isPeelItself,
              !app.isFromSetapp, app.webApp == nil, app.enclosingPackage == nil
        else { return false }
        if let identifier = app.bundleIdentifier {
            if identifier.hasPrefix("com.apple.") || identifier == "com.siveesh.skmole" { return false }
        }
        let path = app.url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "Applications/")
    }

    func scan(_ apps: [PeelCore.InstalledApp]) async {
        guard !isScanning else { return }
        isScanning = true
        resultMessage = nil
        errorMessage = nil
        let eligible = apps.filter(Self.isEligible)
        fromAppStore = apps.filter { $0.isFromAppStore || $0.isSignedByTheAppStore }.count

        let installed = (try? await Homebrew.installedPackages()) ?? []
        let installedCasks = installed.filter { $0.kind == .cask }
        let known = await CaskEvidence.knownCasks(for: eligible)

        var found: [Candidate] = []
        var managed = 0
        for app in eligible {
            if CaskEvidence.installedCask(for: app, in: installedCasks) != nil {
                managed += 1
                continue
            }
            guard let cask = CaskEvidence.cask(for: app, in: known),
                  cask.retirement == nil,
                  cask.installedVersion == nil
            else { continue }
            found.append(Candidate(app: app, cask: cask))
        }

        candidates = found.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        alreadyManaged = managed
        selection = selection.intersection(Set(candidates.map(\.id)))
        hasScanned = true
        isScanning = false
    }

    /// Runs `action` for each selected app in turn. Stops at the first app that is open, so nothing is replaced
    /// under a running program.
    func apply(_ action: Action) async {
        let chosen = candidates.filter { selection.contains($0.id) }
        guard !chosen.isEmpty, workingOn == nil else { return }
        resultMessage = nil
        errorMessage = nil
        transcript = ""
        var done: [String] = []
        var problems: [String] = []

        for candidate in chosen {
            if isRunning(candidate.app) {
                problems.append("\(candidate.app.name) is open. Quit it first, then try again.")
                continue
            }
            workingOn = candidate.id
            if let problem = await run(action, on: candidate) {
                problems.append("\(candidate.app.name): \(problem)")
            } else {
                done.append(candidate.app.name)
            }
        }
        workingOn = nil

        if !done.isEmpty {
            let verb = action == .adopt ? "now managed by Homebrew" : "replaced by Homebrew’s copy"
            resultMessage = "\(done.joined(separator: ", ")) \(done.count == 1 ? "is" : "are") \(verb)."
        }
        if !problems.isEmpty { errorMessage = problems.joined(separator: "\n") }
        selection = []
        await onChanged?()
    }

    /// Run after Homebrew changed an app, so the inventory and Homebrew's lists can refresh.
    var onChanged: (() async -> Void)?

    private func isRunning(_ app: PeelCore.InstalledApp) -> Bool {
        guard let identifier = app.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
    }

    /// Returns nil when it worked, or why it did not.
    private func run(_ action: Action, on candidate: Candidate) async -> String? {
        switch action {
        case .adopt:
            return await install(candidate.cask, adopting: true)
                .map { failure in
                    "Homebrew could not take over this copy, usually because it is not the exact build Homebrew installs. Use Replace instead. (\(failure))"
                }
        case .replace:
            let result = await removal.engine.trash([candidate.app.url], usingHelperFor: [])
            await removal.record(result, source: "Replace \(candidate.app.name) with Homebrew", tool: "homebrew")
            guard result.failures.isEmpty, !result.trashed.isEmpty else {
                let why = result.failures.first.map { RemovalFailureText.describe($0.reason) } ?? "It did not move."
                return "The current copy could not be moved to the Trash, so nothing changed. \(why)"
            }
            if let failure = await install(candidate.cask, adopting: false) {
                return "Homebrew could not install its copy. The previous copy is in the Trash; put it back from History. (\(failure))"
            }
            return nil
        }
    }

    private func install(_ cask: HomebrewPackage, adopting: Bool) async -> String? {
        do {
            let output = try await Homebrew.install(cask, adopting: adopting) { _ in }
            transcript += output
            return nil
        } catch {
            let output = error.output ?? "brew did not finish."
            transcript += output
            return output.split(whereSeparator: \.isNewline).last.map(String.init) ?? output
        }
    }
}
