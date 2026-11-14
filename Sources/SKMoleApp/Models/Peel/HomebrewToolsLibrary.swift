// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import Observation
import PeelCore

/// Homebrew maintenance run through the engine ported from Peel: what is installed where, a cleanup preview and
/// three cleanup strengths, vulnerability checks, tap repair and a Brewfile of this Mac.
@MainActor
@Observable
final class HomebrewToolsLibrary {
    enum CleanupTier: String, CaseIterable, Identifiable {
        case standard
        case olderThan30
        case everyDownload

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: "Standard"
            case .olderThan30: "Older than 30 days"
            case .everyDownload: "Every download"
            }
        }

        var detail: String {
            switch self {
            case .standard: "Removes old versions, stale downloads and formulae nothing needs. This is what Homebrew judges safe."
            case .olderThan30: "Standard, plus every cached file older than 30 days."
            case .everyDownload: "Standard, plus every download except those of what is installed now (brew cleanup --scrub)."
            }
        }

        var engine: Homebrew.Cleanup {
            switch self {
            case .standard: .standard
            case .olderThan30: .olderThan(days: 30)
            case .everyDownload: .everyDownload
            }
        }
    }

    private(set) var installation: HomebrewInstallation?
    private(set) var hasLoadedInstallation = false
    var tier: CleanupTier = .standard
    private(set) var preview: Homebrew.CleanupPreview?
    private(set) var isPreviewing = false
    private(set) var isCleaning = false
    private(set) var output: String?
    private(set) var vulnerabilities: HomebrewVulnerabilityReport?
    private(set) var isCheckingVulnerabilities = false
    private(set) var isRepairing = false
    private(set) var isExporting = false
    private(set) var errorMessage: String?

    private let removal: RemovalService

    init(removal: RemovalService) {
        self.removal = removal
    }

    /// Casks Homebrew still lists although the apps they installed are gone, so it keeps counting them installed.
    private(set) var goneCasks: [HomebrewPackage] = []
    private(set) var hasCheckedForGoneCasks = false
    private(set) var isCheckingForGoneCasks = false
    private(set) var isForgetting = false
    private(set) var forgetMessage: String?

    func findGoneCasks() async {
        guard !isCheckingForGoneCasks else { return }
        isCheckingForGoneCasks = true
        forgetMessage = nil
        let installed = (try? await Homebrew.installedPackages()) ?? []
        goneCasks = installed.filter { $0.kind == .cask && $0.isMissingWhatItInstalled }
        hasCheckedForGoneCasks = true
        isCheckingForGoneCasks = false
    }

    /// Moves Homebrew's record of each gone cask to the Trash, which History can put back.
    func forgetGoneCasks() async {
        guard !isForgetting, !goneCasks.isEmpty else { return }
        isForgetting = true
        let result = await HomebrewReceipt.forget(goneCasks, exclusions: removal.exclusions)
        await removal.record(result, source: "Forget gone Homebrew casks", tool: "homebrew")
        let names = goneCasks.count
        if result.failures.isEmpty {
            forgetMessage = "Homebrew no longer lists \(names) cask\(names == 1 ? "" : "s") whose apps are gone."
        } else {
            forgetMessage = "Some records could not be moved: " + result.failures.prefix(3)
                .map { "\($0.url.lastPathComponent): \(RemovalFailureText.describe($0.reason))" }.joined(separator: "; ")
        }
        isForgetting = false
        await findGoneCasks()
    }

    func loadInstallation() async {
        installation = await Homebrew.installation()
        hasLoadedInstallation = true
    }

    func previewCleanup() async {
        guard !isPreviewing else { return }
        isPreviewing = true
        errorMessage = nil
        if !hasLoadedInstallation { await loadInstallation() }
        preview = await Homebrew.cleanupPreview(asWrittenBy: installation, keeping: [])
        if preview == nil { errorMessage = "Homebrew's dry run could not be read." }
        isPreviewing = false
    }

    func runCleanup() async {
        guard !isCleaning else { return }
        isCleaning = true
        errorMessage = nil
        output = nil
        do {
            output = try await Homebrew.cleanup(tier.engine, keeping: [])
        } catch {
            errorMessage = error.output ?? "Cleanup did not finish."
        }
        preview = nil
        isCleaning = false
    }

    func checkVulnerabilities() async {
        guard !isCheckingVulnerabilities else { return }
        isCheckingVulnerabilities = true
        errorMessage = nil
        if !hasLoadedInstallation { await loadInstallation() }

        if let installation, !installation.checksVulnerabilities {
            errorMessage = "This Homebrew (\(installation.version)) cannot check vulnerabilities. Update Homebrew first."
        } else {
            do {
                vulnerabilities = try await Homebrew.vulnerabilities()
            } catch {
                errorMessage = error.output ?? "The vulnerability check did not finish."
            }
        }
        isCheckingVulnerabilities = false
    }

    func repairTaps() async {
        guard !isRepairing else { return }
        isRepairing = true
        errorMessage = nil
        do {
            output = try await Homebrew.repairTaps()
        } catch {
            errorMessage = error.output ?? "Repairing taps did not finish."
        }
        isRepairing = false
    }

    /// The Brewfile for this Mac, for saving or copying.
    func brewfile() async -> String? {
        guard !isExporting else { return nil }
        isExporting = true
        errorMessage = nil
        if !hasLoadedInstallation { await loadInstallation() }

        var result: String?
        if let installation {
            do {
                result = try await Homebrew.brewfile(from: installation)
            } catch {
                errorMessage = error.output
            }
        } else {
            errorMessage = "Homebrew was not found."
        }
        isExporting = false
        return result
    }
}
