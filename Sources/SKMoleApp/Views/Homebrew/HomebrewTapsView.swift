// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Homebrew taps: list, add, trust and remove.
struct HomebrewTapsView: View {
    @ObservedObject var model: AppModel
    @State private var removing: HomebrewTapsLibrary.Tap?

    private var taps: HomebrewTapsLibrary { model.homebrewTaps }

    var body: some View {
        SectionCard(
            title: "Taps",
            subtitle: "Taps add formulae and casks from other repositories. Homebrew loads an external tap’s packages only once you trust it, so trust a tap only when you trust whoever maintains it.",
            symbol: "point.3.connected.trianglepath.dotted"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                addRow

                if !taps.hasLoaded {
                    ProgressView().controlSize(.small)
                } else if taps.taps.isEmpty {
                    Text("No taps are installed.").font(.subheadline).foregroundStyle(.secondary)
                }

                ForEach(taps.taps) { tap in
                    row(tap)
                }

                if let message = taps.message {
                    Label(message, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(AppPalette.mint)
                }
                if let message = taps.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(AppPalette.amber)
                }
            }
        }
        .task { if !taps.hasLoaded { await taps.load() } }
        .alert(
            "Trust \(taps.justAdded?.name ?? "this tap")?",
            isPresented: Binding(get: { taps.justAdded != nil }, set: { if !$0 { taps.justAdded = nil } })
        ) {
            Button("Trust Tap") {
                if let tap = taps.justAdded { Task { await taps.setTrusted(true, for: tap) } }
                taps.justAdded = nil
            }
            Button("Not Now", role: .cancel) { taps.justAdded = nil }
        } message: {
            let tap = taps.justAdded
            Text("The tap is added, but Homebrew will not load its \(tap?.packageCount ?? 0) package\(tap?.packageCount == 1 ? "" : "s") until you trust it. Trusting lets Homebrew run code from \(tap?.remote ?? "this repository"). You can stop trusting it at any time.")
        }
        .alert(
            "Remove \(removing?.name ?? "this tap")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button("Remove Tap", role: .destructive) {
                if let tap = removing { Task { await taps.remove(tap) } }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Homebrew removes the tap’s local copy. It refuses while anything installed from the tap is still installed.")
        }
    }

    // MARK: Add

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("user/repo, for example homebrew/cask-fonts", text: Binding(get: { taps.newName }, set: { taps.newName = $0 }))
                    .textFieldStyle(.roundedBorder)
                TextField("Git URL (optional)", text: Binding(get: { taps.newURL }, set: { taps.newURL = $0 }))
                    .textFieldStyle(.roundedBorder)
                Button("Add Tap", systemImage: "plus") { Task { await taps.add() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!taps.canAdd || taps.isWorking)
                if taps.isWorking { ProgressView().controlSize(.small) }
            }
            Text("Without a URL Homebrew clones github.com/user/homebrew-repo over HTTPS. A URL may be https, ssh or git.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Rows

    private func row(_ tap: HomebrewTapsLibrary.Tap) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tap.official ? "checkmark.seal" : (tap.trusted ? "lock.open" : "lock"))
                .foregroundStyle(tap.official || tap.trusted ? AppPalette.mint : AppPalette.amber)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tap.name).font(.subheadline.weight(.semibold))
                    if tap.official {
                        Pill(title: "Official", tint: AppPalette.sky)
                    } else {
                        Pill(title: tap.trusted ? "Trusted" : "Not trusted", tint: tap.trusted ? AppPalette.mint : AppPalette.amber)
                    }
                    if tap.isPrivate { Pill(title: "Private", tint: AppPalette.sky) }
                }
                Text(detail(tap)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if !tap.official {
                Button(tap.trusted ? "Untrust" : "Trust") { Task { await taps.setTrusted(!tap.trusted, for: tap) } }
                    .buttonStyle(.bordered)
                    .disabled(taps.isWorking)
                Button("Remove", role: .destructive) { removing = tap }
                    .buttonStyle(.bordered)
                    .disabled(taps.isWorking)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detail(_ tap: HomebrewTapsLibrary.Tap) -> String {
        var parts = ["\(tap.formulaNames.count) formulae", "\(tap.caskTokens.count) casks"]
        if let remote = tap.remote { parts.append(remote) }
        if let commit = tap.lastCommit { parts.append("updated \(commit)") }
        return parts.joined(separator: " · ")
    }
}
