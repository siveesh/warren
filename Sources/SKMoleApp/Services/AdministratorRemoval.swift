// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore
import PeelPrivileged

/// Whether Warren may ask for administrator rights when something it removes is owned by root.
enum AdministratorRights: String, CaseIterable, Identifiable {
    case askEachTime
    case never

    static let defaultsKey = "skmole.administratorRights"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askEachTime: "Ask me when something needs them"
        case .never: "Never use administrator rights"
        }
    }

    var subtitle: String {
        switch self {
        case .askEachTime:
            "Items owned by the system are listed with a lock. If you select them, Warren shows exactly which ones need administrator rights and macOS asks for your password or Touch ID before anything moves."
        case .never:
            "Items that need administrator rights are shown but cannot be selected. Warren only changes what your own account may change."
        }
    }

    static var current: AdministratorRights {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AdministratorRights.init(rawValue:)) ?? .askEachTime
    }
}

/// Moves root-owned items to the Trash after the user approved it. Each item is judged by the engine's guard again
/// right before it moves. With Warren's helper installed the helper moves them, under its own path policy and ledger,
/// and an account that is not an administrator needs an administrator's approval. Without it, macOS shows its own
/// authentication prompt for the whole batch.
enum AdministratorRemoval {
    struct Outcome {
        var moved: [URL] = []
        var failures: [(url: URL, reason: String)] = []
        var cancelled = false
        /// What moved, as History keeps it.
        var trashed: [TrashedItem] = []
        /// Which way the items went, for the message the person reads.
        var usedHelper = false
    }

    /// Moves `urls`, then hands what moved to `recording` so History lists it.
    static func moveToTrash(
        _ urls: [URL],
        engine: TrashService,
        recording: (@Sendable (TrashResult) async -> Void)? = nil
    ) async -> Outcome {
        var outcome = Outcome()
        var allowed: [URL] = []
        for url in urls {
            if let reason = engine.refusal(of: url) {
                outcome.failures.append((url, RemovalFailureText.describe(reason)))
            } else {
                allowed.append(url)
            }
        }
        guard !allowed.isEmpty else { return outcome }

        if PrivilegedHelper.status == .enabled, await PrivilegedHelper.isResponding() {
            outcome.usedHelper = true
            for start in stride(from: 0, to: allowed.count, by: HelperRequest.maximumItems) {
                let batch = Array(allowed[start..<min(start + HelperRequest.maximumItems, allowed.count)])
                let result = await PrivilegedHelper.moveToTrash(batch)
                outcome.trashed += result.trashed
                outcome.moved += result.trashed.map(\.originalURL)
                outcome.failures += result.failures.map { ($0.url, RemovalFailureText.describe($0.reason)) }
            }
        } else {
            await moveWithAdministratorPrompt(allowed, into: &outcome)
        }

        if let recording, !outcome.trashed.isEmpty {
            await recording(TrashResult(trashed: outcome.trashed))
        }
        return outcome
    }

    private static func moveWithAdministratorPrompt(_ allowed: [URL], into outcome: inout Outcome) async {
        var commands: [String] = []
        var indexed: [(url: URL, destination: URL)] = []
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let stamp = Int(Date().timeIntervalSince1970)

        for url in allowed {
            let index = indexed.count
            let destination = trash.appendingPathComponent("\(url.lastPathComponent) \(stamp)-\(index)")
            commands.append("/bin/mv -n \(shellQuoted(url.path)) \(shellQuoted(destination.path)) && echo OK\(index) || echo FAIL\(index)")
            indexed.append((url, destination))
        }

        let result = await runWithAdministratorPrivileges(commands.joined(separator: "; "))
        if result.cancelled {
            outcome.cancelled = true
            return
        }

        for (index, entry) in indexed.enumerated() {
            if result.output.contains("OK\(index)") {
                outcome.moved.append(entry.url)
                outcome.trashed.append(.moved(from: entry.url, to: entry.destination))
            } else {
                outcome.failures.append((entry.url, result.error ?? "The move did not complete."))
            }
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runWithAdministratorPrivileges(_ command: String) async -> (output: String, error: String?, cancelled: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let escaped = command
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
                let output = Pipe()
                let error = Pipe()
                process.standardOutput = output
                process.standardError = error

                do {
                    try process.run()
                    process.waitUntilExit()
                    let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let err = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let cancelled = err.contains("-128") || err.localizedCaseInsensitiveContains("User canceled")
                    continuation.resume(returning: (out, err.isEmpty ? nil : err, cancelled))
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription, false))
                }
            }
        }
    }
}
