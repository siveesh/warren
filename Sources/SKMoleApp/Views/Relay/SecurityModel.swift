import RelayAppSupport
import Foundation
import Observation
import RelaySecurity

/// Observable view model for the security settings: Touch ID detection and elevated operations.
@MainActor
@Observable
final class SecurityModel {

    private let detector = SudoDetector()

    var touchIDHardware = false
    var sudoStatus: TouchIDSudoStatus = .unknown
    var message: String?

    var enableGuidanceCommand: String { SudoDetector.enableGuidanceCommand }

    func refresh() {
        touchIDHardware = detector.hasTouchIDHardware()
        sudoStatus = detector.touchIDStatus()
    }

    func performOperation(_ operation: PrivilegedOperation) {
        guard let command = operation.elevatedShellCommand else {
            message = "\(operation.summary) requires parameters — add it as a command with 'Requires Elevation' enabled."
            return
        }
        message = nil
        Task {
            let (ok, output) = await Self.runElevated(command)
            message = ok ? "✓ \(operation.summary) completed." : "Failed: \(output)"
        }
    }

    private static func runElevated(_ command: String) async -> (Bool, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let escaped = command
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let script = "do shell script \"\(escaped)\" with administrator privileges"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: (true, ""))
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let out = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(returning: (false, out.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
}
