// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SKMoleShared

/// Warren's fixed maintenance tasks. The helper runs only these, by identifier, and never a command a client hands it.
enum MaintenanceTasks {
    private static let purgeableReclaimTargetBytes = "10737418240"

    static func run(_ task: PrivilegedMaintenanceTask) async throws -> String {
        guard getuid() == 0 else { throw MaintenanceError.rootRequired }

        switch task {
        case .flushDNSCache:
            let flush = try await runProcess("/usr/bin/dscacheutil", ["-flushcache"])
            let mdns = try await runProcess("/usr/bin/killall", ["-HUP", "mDNSResponder"])
            let output = [flush, mdns].filter { !$0.isEmpty }.joined(separator: "\n")
            return output.isEmpty ? "DNS cache refresh completed." : output
        case .freePurgeableSpace:
            let output = try await runProcess("/usr/bin/tmutil", ["thinlocalsnapshots", "/", purgeableReclaimTargetBytes, "4"])
            return output.isEmpty ? "macOS finished thinning local snapshots to reclaim purgeable space where possible." : output
        case .runPeriodicDaily:
            let output = try await runProcess("/usr/sbin/periodic", ["daily"])
            return output.isEmpty ? "Daily periodic maintenance completed." : output
        }
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw MaintenanceError.missingExecutable(executable)
        }
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: executable.hasSuffix("/tmutil") ? 90 : 30,
            maxOutputBytes: 1_024 * 1_024
        )
        guard result.terminationStatus == 0 else {
            throw MaintenanceError.failed(result.output.isEmpty ? "\(executable) exited with status \(result.terminationStatus)." : result.output)
        }
        return result.output
    }
}

private enum MaintenanceError: LocalizedError {
    case rootRequired
    case missingExecutable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .rootRequired: "This helper must run as root."
        case .missingExecutable(let path): "Required executable not found: \(path)"
        case .failed(let output): output
        }
    }
}
