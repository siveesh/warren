// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import PeelCore
import RelayAppSupport
import SKMoleShared

/// Homebrew actions of the app model: opening packages, search, selection, install, upgrade, uninstall, services and
/// doctor clean-up. State lives in `AppModel`.
extension AppModel {
    func openMagikaInHomebrew() async {
        let magikaResult = HomebrewPackageSearchResult.featured.first(where: { $0.reference == MagikaStatus.homebrewReference })
            ?? HomebrewPackageSearchResult(
                reference: MagikaStatus.homebrewReference,
                displayName: "Magika",
                description: "AI-powered file content type detection",
                source: "Recommended formula",
                bundleIdentifier: nil
            )

        await selectHomebrewSearchResult(magikaResult)
    }

    func searchHomebrewPackages() async {
        homebrewSearchTask?.cancel()
        let requestID = UUID()
        homebrewSearchRequestID = requestID
        homebrewSearchBusy = true
        homebrewError = nil

        let query = homebrewSearchQuery
        let service = homebrewService
        let task = Task { [requestID] in
            do {
                return try await service.searchPackages(query: query)
            } catch {
                await MainActor.run {
                    guard self.homebrewSearchRequestID == requestID else { return }
                    self.homebrewError = error.localizedDescription
                }

                return HomebrewPackageSearchResult.featured
            }
        }
        homebrewSearchTask = task

        let results = await task.value
        guard homebrewSearchRequestID == requestID else { return }

        homebrewSearchResults = results
        homebrewSearchBusy = false
        homebrewSearchTask = nil
    }

    /// `navigate: false` pre-selects the package without switching sections, for background loads
    /// (for example while the Updates tab refreshes Homebrew).
    func selectHomebrewInstalledPackage(_ package: HomebrewInstalledPackage, navigate: Bool = true) async {
        if navigate {
            selection = .homebrew
        }
        homebrewSelectedPackageDetail = nil
        homebrewSelectedFallbackResult = HomebrewPackageSearchResult(
            reference: package.reference,
            displayName: package.displayName,
            description: package.description,
            source: "Installed package",
            bundleIdentifier: nil
        )
        await loadHomebrewPackageDetail(for: package.reference)
    }

    func selectHomebrewSearchResult(_ result: HomebrewPackageSearchResult) async {
        selection = .homebrew
        homebrewSelectedPackageDetail = nil
        homebrewSelectedFallbackResult = result
        await loadHomebrewPackageDetail(for: result.reference)
    }

    func openHomebrewInstallGuide() {
        NSWorkspace.shared.open(HomebrewStatus.installGuideURL)
    }

    func launchHomebrewInstallerInTerminal() {
        homebrewError = nil
        launchTerminalCommand(HomebrewStatus.installCommand) { [weak self] message in
            self?.homebrewError = message
        }
    }

    func openHomebrewHomepage() {
        guard let url = selectedHomebrewDetail?.homepage else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshGitHubCLI() async {
        await loadGitHubCLI(force: true)
    }

    func installGitHubCLI() async {
        guard homebrewStatus.isInstalled else {
            gitHubCLIError = "Install Homebrew first, then Warren can install GitHub CLI with brew."
            return
        }

        let log = await executeHomebrewCommand(
            arguments: ["install", "gh"],
            actionTitle: "Install GitHub CLI",
            actionID: "install:gh-cli"
        )

        if log.succeeded {
            await loadGitHubCLI(force: true)
        }
    }

    /// Saves a new personal access token to the Keychain via `gh`, then refreshes the account status.
    func updateGitHubToken(_ token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            gitHubCLIError = "Paste a token first."
            return false
        }

        gitHubCLIError = nil
        gitHubCLIBusy = true
        let log = await gitHubCLIService.storeToken(trimmed)
        gitHubCLIBusy = false

        guard log.succeeded else {
            gitHubCLIError = log.output
            return false
        }

        await loadGitHubCLI(force: true)
        return true
    }

    func launchGitHubCLILoginInTerminal() {
        gitHubCLIError = nil
        launchTerminalCommand(GitHubCLIStatus.authCommand) { [weak self] message in
            self?.gitHubCLIError = message
        }
    }

    func openGitHubCLIHomepage() {
        NSWorkspace.shared.open(GitHubCLIStatus.homepageURL)
    }

    func openGitHubCLILoginGuide() {
        NSWorkspace.shared.open(GitHubCLIStatus.authGuideURL)
    }

    func openGitHubPersonalAccessTokenPage() {
        NSWorkspace.shared.open(GitHubCLIStatus.personalAccessTokenURL)
    }

    func openGitHubPersonalAccessTokenDocs() {
        NSWorkspace.shared.open(GitHubCLIStatus.personalAccessTokenDocsURL)
    }

    /// Relay's palette lives in the menu bar companion, so ask it to open the palette.
    func openRelayPalette() {
        RelayShared.requestPalette()
    }

    func openGitHubRepository(_ repository: GitHubRepositorySummary) {
        NSWorkspace.shared.open(repository.url)
    }

    func runHomebrewMaintenance(_ action: HomebrewMaintenanceAction) async {
        let log = await executeHomebrewCommand(
            arguments: action.arguments,
            actionTitle: action.title,
            actionID: "maintenance:\(action.id)"
        )

        guard action == .doctor else {
            return
        }

        homebrewDoctorLastOutput = log.output
        homebrewDoctorIssues = HomebrewService.parseDoctorIssues(from: log.output)
    }

    func installSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: installationArguments(for: detail.reference),
            actionTitle: "Install \(detail.displayName)",
            actionID: "install:\(detail.id)"
        )
    }

    func upgradeSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: upgradeArguments(for: detail.reference),
            actionTitle: "Upgrade \(detail.displayName)",
            actionID: "upgrade:\(detail.id)"
        )
    }

    func reinstallSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: reinstallArguments(for: detail.reference),
            actionTitle: "Reinstall \(detail.displayName)",
            actionID: "reinstall:\(detail.id)"
        )
    }

    func uninstallSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: uninstallArguments(for: detail.reference),
            actionTitle: "Uninstall \(detail.displayName)",
            actionID: "uninstall:\(detail.id)"
        )
    }

    func cleanupSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: ["cleanup", detail.token],
            actionTitle: "Cleanup \(detail.displayName)",
            actionID: "cleanup:\(detail.id)"
        )
    }

    func runHomebrewServiceAction(_ verb: String, packageToken: String) async {
        await executeHomebrewCommand(
            arguments: ["services", verb, packageToken],
            actionTitle: "brew services \(verb) \(packageToken)",
            actionID: "service:\(verb):\(packageToken)"
        )
    }

    func deleteHomebrewDoctorPath(_ path: HomebrewDoctorIssuePath) async {
        let actionID = "doctor-delete:\(path.id)"
        homebrewBusyActionID = actionID
        homebrewError = nil

        do {
            try guardService.removePermanently(URL(fileURLWithPath: path.path), purpose: .developerTooling)

            homebrewLogs.insert(
                OptimizationLog(
                    actionTitle: "Delete \(path.fileName)",
                    output: "Removed \(path.path)",
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )

            homebrewDoctorIssues = homebrewDoctorIssues.compactMap { issue in
                let remainingPaths = issue.paths.filter { $0.path != path.path }
                if issue.paths.isEmpty || remainingPaths.isEmpty {
                    return nil
                }

                return HomebrewDoctorIssue(
                    title: issue.title,
                    summary: issue.summary,
                    paths: remainingPaths,
                    supportingLines: issue.supportingLines
                )
            }

            await runHomebrewMaintenance(.doctor)
        } catch {
            homebrewError = error.localizedDescription
            homebrewLogs.insert(
                OptimizationLog(
                    actionTitle: "Delete \(path.fileName)",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        homebrewBusyActionID = nil
    }
}
