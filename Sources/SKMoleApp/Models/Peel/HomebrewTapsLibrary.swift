// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import SKMoleShared

/// Homebrew taps: the list, adding one (from GitHub or any git URL), trusting or untrusting a tap's formulae and casks,
/// and removing one. Homebrew will not load an external tap's packages until the tap is trusted.
@MainActor
@Observable
final class HomebrewTapsLibrary {
    struct Tap: Identifiable, Hashable, Decodable {
        let name: String
        let official: Bool
        let trusted: Bool
        let remote: String?
        let customRemote: Bool
        let isPrivate: Bool
        let formulaNames: [String]
        let caskTokens: [String]
        let branch: String?
        let lastCommit: String?

        var id: String { name }
        var packageCount: Int { formulaNames.count + caskTokens.count }

        enum CodingKeys: String, CodingKey {
            case name, official, trusted, remote, branch
            case customRemote = "custom_remote"
            case isPrivate = "private"
            case formulaNames = "formula_names"
            case caskTokens = "cask_tokens"
            case lastCommit = "last_commit"
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            official = try values.decodeIfPresent(Bool.self, forKey: .official) ?? false
            trusted = try values.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
            remote = try values.decodeIfPresent(String.self, forKey: .remote)
            customRemote = try values.decodeIfPresent(Bool.self, forKey: .customRemote) ?? false
            isPrivate = try values.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
            formulaNames = try values.decodeIfPresent([String].self, forKey: .formulaNames) ?? []
            caskTokens = try values.decodeIfPresent([String].self, forKey: .caskTokens) ?? []
            branch = try values.decodeIfPresent(String.self, forKey: .branch)
            lastCommit = try values.decodeIfPresent(String.self, forKey: .lastCommit)
        }
    }

    private(set) var taps: [Tap] = []
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    private(set) var message: String?
    private(set) var errorMessage: String?
    /// A tap just added that is not trusted yet, so the view can ask whether to trust it.
    var justAdded: Tap?

    var newName = ""
    var newURL = ""

    // MARK: Validation

    /// `user/repo`, as Homebrew names a tap.
    static func isValidName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) && !$0.hasPrefix("-") }
    }

    /// A remote Homebrew's git can clone: https, http, ssh or git. Nothing starting with `-` reaches the command line.
    static func isValidRemote(_ remote: String) -> Bool {
        guard !remote.isEmpty, !remote.hasPrefix("-"), !remote.contains(where: \.isWhitespace) else { return false }
        return ["https://", "http://", "ssh://", "git://", "git@"].contains { remote.hasPrefix($0) }
    }

    var canAdd: Bool {
        Self.isValidName(newName.trimmingCharacters(in: .whitespaces))
            && (newURL.trimmingCharacters(in: .whitespaces).isEmpty || Self.isValidRemote(newURL.trimmingCharacters(in: .whitespaces)))
    }

    // MARK: Actions

    func load() async {
        guard let brew = Self.brewPath else {
            errorMessage = "Homebrew was not found."
            hasLoaded = true
            return
        }
        let result = await Self.run(brew, ["tap-info", "--installed", "--json"])
        taps = Self.parse(result.output).sorted {
            ($0.official ? 0 : 1, $0.name) < ($1.official ? 0 : 1, $1.name)
        }
        if result.status != 0, taps.isEmpty { errorMessage = Self.lastLine(result.output) }
        hasLoaded = true
    }

    func add() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let url = newURL.trimmingCharacters(in: .whitespaces)
        guard canAdd, let brew = Self.brewPath, !isWorking else { return }
        isWorking = true
        message = nil
        errorMessage = nil
        // `--` keeps a tap name or URL from ever being read as an option.
        let result = await Self.run(brew, ["tap", "--", name] + (url.isEmpty ? [] : [url]), timeout: 300)
        if result.status == 0 {
            newName = ""
            newURL = ""
            await load()
            if let added = taps.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                message = "Added \(added.name) with \(added.packageCount) package\(added.packageCount == 1 ? "" : "s")."
                if !added.trusted { justAdded = added }
            }
        } else {
            errorMessage = Self.lastLine(result.output)
        }
        isWorking = false
    }

    func setTrusted(_ trusted: Bool, for tap: Tap) async {
        guard let brew = Self.brewPath, !isWorking else { return }
        isWorking = true
        message = nil
        errorMessage = nil
        let result = await Self.run(brew, [trusted ? "trust" : "untrust", "--tap", "--", tap.name])
        if result.status == 0 {
            message = trusted ? "Homebrew now loads packages from \(tap.name)." : "Homebrew no longer loads packages from \(tap.name)."
        } else {
            errorMessage = Self.lastLine(result.output)
        }
        await load()
        isWorking = false
    }

    func remove(_ tap: Tap) async {
        guard !tap.official, let brew = Self.brewPath, !isWorking else { return }
        isWorking = true
        message = nil
        errorMessage = nil
        // Without --force, Homebrew refuses while anything from the tap is installed, which is what we want.
        let result = await Self.run(brew, ["untap", "--", tap.name], timeout: 120)
        if result.status == 0 {
            message = "Removed \(tap.name)."
        } else {
            errorMessage = Self.lastLine(result.output)
        }
        await load()
        isWorking = false
    }

    // MARK: Process

    private static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ brew: String, _ arguments: [String], timeout: TimeInterval = 60) async -> (status: Int32, output: String) {
        var environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: brew).deletingLastPathComponent().path
        environment["PATH"] = [directory, "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        do {
            let result = try await ProcessRunner.run(
                executable: brew, arguments: arguments, environment: environment, timeout: timeout,
                maxOutputBytes: 8 * 1_024 * 1_024
            )
            return (result.terminationStatus, result.output)
        } catch {
            return (1, error.localizedDescription)
        }
    }

    static func parse(_ output: String) -> [Tap] {
        guard let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]"), start < end,
              let data = String(output[start...end]).data(using: .utf8)
        else { return [] }
        return (try? JSONDecoder().decode([Tap].self, from: data)) ?? []
    }

    private static func lastLine(_ output: String) -> String {
        output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? "Homebrew did not finish."
    }
}
