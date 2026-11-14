// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore

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
/// right before it moves, and macOS shows its own authentication prompt for the whole batch.
enum AdministratorRemoval {
    struct Outcome {
        var moved: [URL] = []
        var failures: [(url: URL, reason: String)] = []
        var cancelled = false
    }

    static func moveToTrash(_ urls: [URL], engine: TrashService) async -> Outcome {
        var outcome = Outcome()
        var commands: [String] = []
        var indexed: [URL] = []
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let stamp = Int(Date().timeIntervalSince1970)

        for url in urls {
            if let reason = engine.refusal(of: url) {
                outcome.failures.append((url, RemovalFailureText.describe(reason)))
                continue
            }

            let index = indexed.count
            let destination = trash.appendingPathComponent("\(url.lastPathComponent) \(stamp)-\(index)")
            commands.append("/bin/mv -n \(shellQuoted(url.path)) \(shellQuoted(destination.path)) && echo OK\(index) || echo FAIL\(index)")
            indexed.append(url)
        }

        guard !commands.isEmpty else { return outcome }

        let script = commands.joined(separator: "; ")
        let result = await runWithAdministratorPrivileges(script)

        if result.cancelled {
            outcome.cancelled = true
            return outcome
        }

        for (index, url) in indexed.enumerated() {
            if result.output.contains("OK\(index)") {
                outcome.moved.append(url)
            } else {
                outcome.failures.append((url, result.error ?? "The move did not complete."))
            }
        }

        return outcome
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
