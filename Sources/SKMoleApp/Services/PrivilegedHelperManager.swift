import Foundation
import PeelCore
import ServiceManagement
import SKMoleShared

struct PrivilegedHelperManager: Sendable {
    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: PrivilegedHelperConstants.plistName)
    }

    private var helperExecutableURL: URL? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools/\(PrivilegedHelperConstants.helperExecutableName)")
    }

    func status() -> PrivilegedHelperState {
        switch daemonService.status {
        case .enabled:
            PrivilegedHelperState(
                summary: "Installed",
                detail: "The privileged helper is registered and available for admin-only maintenance.",
                isEnabled: true,
                requiresApproval: false
            )
        case .requiresApproval:
            PrivilegedHelperState(
                summary: "Approval required",
                detail: "macOS still needs approval for the helper registration in Login Items or system settings.",
                isEnabled: false,
                requiresApproval: true
            )
        case .notFound:
            PrivilegedHelperState(
                summary: "Bundle assets missing",
                detail: "The packaged app does not currently contain the helper plist or helper executable.",
                isEnabled: false,
                requiresApproval: false
            )
        case .notRegistered:
            .unavailable
        @unknown default:
            PrivilegedHelperState(
                summary: "Unknown",
                detail: "The helper returned an unrecognized ServiceManagement status.",
                isEnabled: false,
                requiresApproval: false
            )
        }
    }

    func register() throws -> PrivilegedHelperState {
        try daemonService.register()
        return status()
    }

    func unregister() throws -> PrivilegedHelperState {
        try daemonService.unregister()
        return status()
    }

    func diagnosticSummary() async -> String? {
        if let signingIssue = await signingIssueSummary() {
            return signingIssue
        }

        guard FileManager.default.isExecutableFile(atPath: "/bin/launchctl") else {
            return nil
        }

        guard let result = try? await ProcessRunner.run(
            executable: "/bin/launchctl",
            arguments: ["print", "system/\(PrivilegedHelperConstants.daemonLabel)"],
            timeout: 6,
            maxOutputBytes: 512 * 1_024
        ) else {
            return nil
        }

        let output = result.output

        guard !output.isEmpty else {
            return nil
        }

        let interestingPrefixes = [
            "state =",
            "path =",
            "program =",
            "last exit code =",
            "reason ="
        ]
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                interestingPrefixes.contains(where: { line.hasPrefix($0) })
            }

        if !lines.isEmpty {
            return "launchctl: " + lines.joined(separator: " | ")
        }

        if result.terminationStatus != 0 {
            return "launchctl: \(output)"
        }

        return nil
    }

    private func signingIssueSummary() async -> String? {
        if let helperExecutableURL,
           let helperSignature = await signatureSummary(for: helperExecutableURL),
           helperSignature.requiresTrustedSigning {
            return "The embedded privileged helper is \(helperSignature.signatureDescription). macOS blocks launch daemons unless they are signed with a trusted Apple certificate. Rebuild Warren with `SKMOLE_CODESIGN_IDENTITY` set to a valid `Apple Development` or `Developer ID Application` identity, then reinstall the helper."
        }

        if let appSignature = await signatureSummary(for: Bundle.main.bundleURL),
           appSignature.requiresTrustedSigning {
            return "The main app bundle is \(appSignature.signatureDescription). The privileged helper cannot satisfy macOS launch constraints until the whole app is signed with a trusted Apple certificate and reinstalled."
        }

        return nil
    }

    private func signatureSummary(for url: URL) async -> SignatureSummary? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") || FileManager.default.fileExists(atPath: "/usr/bin/codesign") else {
            return nil
        }

        guard let result = try? await ProcessRunner.run(
            executable: "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=4", url.path],
            timeout: 8,
            maxOutputBytes: 512 * 1_024
        ) else {
            return nil
        }

        let output = result.output

        let signature = output
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("Signature=") })
            .map { entry in
                String(entry.split(separator: "=", maxSplits: 1).last ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        let teamIdentifier = output
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("TeamIdentifier=") })
            .map { entry in
                String(entry.split(separator: "=", maxSplits: 1).last ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        guard let signature else {
            return nil
        }

        let normalizedTeamIdentifier: String?
        if let teamIdentifier, !teamIdentifier.isEmpty, teamIdentifier != "not set" {
            normalizedTeamIdentifier = teamIdentifier
        } else {
            normalizedTeamIdentifier = nil
        }

        return SignatureSummary(signature: signature, teamIdentifier: normalizedTeamIdentifier)
    }

    nonisolated func ping() async throws -> String {
        guard await PrivilegedHelper.isResponding() else { throw PrivilegedHelperError.notAnswering }
        return "ready"
    }

    nonisolated func run(_ task: PrivilegedMaintenanceTask) async throws -> String {
        let answer = await PrivilegedHelper.runMaintenanceTask(task.rawValue)
        guard answer.succeeded else { throw PrivilegedHelperError.remoteFailure(answer.message) }
        return answer.message
    }
}

private enum PrivilegedHelperError: LocalizedError {
    case remoteFailure(String)
    case notAnswering

    var errorDescription: String? {
        switch self {
        case let .remoteFailure(message): message
        case .notAnswering: "The privileged helper did not answer. Reinstall it from Optimize."
        }
    }
}

private struct SignatureSummary {
    let signature: String
    let teamIdentifier: String?

    var requiresTrustedSigning: Bool {
        signature.caseInsensitiveCompare("adhoc") == .orderedSame || teamIdentifier == nil
    }

    var signatureDescription: String {
        if signature.caseInsensitiveCompare("adhoc") == .orderedSame {
            return "ad-hoc signed"
        }

        if let teamIdentifier {
            return "signed without a usable trusted team chain (\(teamIdentifier))"
        }

        return "signed without a usable trusted team chain"
    }
}
