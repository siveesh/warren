// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from the author's own Xcode Cleaner (XcodeCleanerCore: RuntimeParser, simctl calls).
import Foundation

/// An installed simulator runtime, as `xcrun simctl runtime list -v` reports it.
struct SimulatorRuntime: Identifiable, Hashable, Sendable {
    let id: String
    let platform: String
    let version: String
    let build: String
    let size: String
    let lastUsed: String

    var title: String { "\(platform) \(version) (\(build))" }
}

enum SimulatorRuntimeParser {
    static func parse(_ text: String) -> [SimulatorRuntime] {
        let pattern = #"(?m)^(iOS|watchOS|tvOS|visionOS)\s+([\d.]+)\s+\(([^)]+)\)\s+-\s+([A-Fa-f0-9-]{36})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.enumerated().map { index, match in
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
            return SimulatorRuntime(
                id: ns.substring(with: match.range(at: 4)),
                platform: ns.substring(with: match.range(at: 1)),
                version: ns.substring(with: match.range(at: 2)),
                build: ns.substring(with: match.range(at: 3)),
                size: capture(#"Size:\s*(\S+)"#, in: block) ?? "Unknown",
                lastUsed: capture(#"Last Used At:\s*(\S+)"#, in: block) ?? "Never"
            )
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

/// Runs `xcrun simctl` off the main actor. Warren only lists runtimes and deletes the ones the user chose, plus
/// simulator devices Xcode itself reports as unavailable. It never erases simulator content.
enum SimulatorTools {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @concurrent
    static func runtimes() async -> [SimulatorRuntime]? {
        guard let output = try? run(["runtime", "list", "-v"]) else { return nil }
        return SimulatorRuntimeParser.parse(output)
    }

    @concurrent
    static func delete(runtimeIDs: [String]) async -> [String] {
        var failures: [String] = []
        for id in runtimeIDs {
            // Only identifiers simctl itself printed are passed on.
            guard UUID(uuidString: id) != nil else { failures.append("Invalid runtime identifier: \(id)"); continue }
            do { try run(["runtime", "delete", id]) } catch { failures.append(error.localizedDescription) }
        }
        return failures
    }

    @concurrent
    static func deleteUnavailableDevices() async -> String? {
        do { try run(["delete", "unavailable"]); return nil } catch { return error.localizedDescription }
    }

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure(message: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}
