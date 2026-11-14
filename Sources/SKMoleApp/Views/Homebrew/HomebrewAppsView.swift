// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PeelCore
import SwiftUI

/// Apps put on this Mac by hand that Homebrew has a cask for, and casks whose apps are gone.
struct HomebrewAppsView: View {
    @ObservedObject var model: AppModel
    @State private var confirming: CaskReplacementLibrary.Action?
    @State private var confirmingForget = false

    private var library: CaskReplacementLibrary { model.caskReplacement }
    private var tools: HomebrewToolsLibrary { model.homebrewTools }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            replaceCard
            goneCasksCard
        }
        .alert(
            confirming == .replace ? "Replace with Homebrew’s copy?" : "Hand these apps to Homebrew?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
        ) {
            Button(confirming?.title ?? "Continue") {
                if let action = confirming { Task { await library.apply(action) } }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text(confirming == .replace
                 ? "Each selected app moves to the Trash first, then Homebrew installs its own copy. Your settings and data stay where they are. If Homebrew fails, put the app back from History."
                 : "Homebrew takes over the copy you have, which stays where it is with its settings. This works only when it is the exact build Homebrew installs; if not, nothing changes.")
        }
        .alert("Forget these casks?", isPresented: $confirmingForget) {
            Button("Forget \(tools.goneCasks.count)") { Task { await tools.forgetGoneCasks() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew’s record of each cask moves to the Trash, so Homebrew stops listing it. The apps are already gone. History can put a record back.")
        }
    }

    // MARK: Replace

    private var replaceCard: some View {
        SectionCard(
            title: "Apps you could manage with Homebrew",
            subtitle: "Apps installed by hand, not from the App Store, that Homebrew has a cask for. Homebrew can keep them up to date.",
            symbol: "arrow.triangle.2.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button(library.hasScanned ? "Check Again" : "Find Apps", systemImage: "magnifyingglass") {
                        Task {
                            let apps = model.appLibrary.apps.isEmpty ? await model.appLibrary.rescan() : model.appLibrary.apps
                            await library.scan(apps)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.isScanning || library.workingOn != nil)

                    if library.isScanning || library.workingOn != nil { ProgressView().controlSize(.small) }
                }

                if library.hasScanned {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }

                if library.candidates.isEmpty, library.hasScanned, !library.isScanning {
                    Text("No app here has a Homebrew cask waiting.").font(.subheadline).foregroundStyle(.secondary)
                }

                ForEach(library.candidates) { candidate in
                    row(candidate)
                }

                if !library.candidates.isEmpty {
                    HStack(spacing: 12) {
                        Button(CaskReplacementLibrary.Action.adopt.title) { confirming = .adopt }
                            .buttonStyle(.bordered)
                            .disabled(library.selection.isEmpty || library.workingOn != nil)
                        Button(CaskReplacementLibrary.Action.replace.title) { confirming = .replace }
                            .buttonStyle(.bordered)
                            .disabled(library.selection.isEmpty || library.workingOn != nil)
                        Spacer()
                        Button(library.selection.count == library.candidates.count ? "Select None" : "Select All") {
                            library.selection = library.selection.count == library.candidates.count
                                ? [] : Set(library.candidates.map(\.id))
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("Hand to Homebrew keeps your copy and only works when it is the exact build Homebrew installs. Replace moves your copy to the Trash and installs Homebrew’s, which always works for apps that are closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message = library.resultMessage {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(AppPalette.mint).font(.subheadline)
                }
                if let message = library.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(AppPalette.amber).font(.subheadline)
                }
            }
        }
    }

    private var summary: String {
        var parts = ["\(library.candidates.count) can move to Homebrew"]
        if library.alreadyManaged > 0 { parts.append("\(library.alreadyManaged) already managed by Homebrew") }
        if library.fromAppStore > 0 { parts.append("\(library.fromAppStore) from the App Store, left alone") }
        return parts.joined(separator: " · ")
    }

    private func row(_ candidate: CaskReplacementLibrary.Candidate) -> some View {
        let selected = library.selection.contains(candidate.id)
        return HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            AppIconThumbnail(url: candidate.app.url, size: 26, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.app.name).font(.subheadline.weight(.semibold))
                Text("\(candidate.app.version.map { "Version \($0) · " } ?? "")brew install --cask \(candidate.cask.fullName)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let latest = candidate.cask.latestVersion {
                Pill(title: "Homebrew: \(latest)", tint: AppPalette.sky)
            }
            if candidate.hasOwnUpdater { Pill(title: "Updates itself", tint: AppPalette.amber) }
            if library.workingOn == candidate.id { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            guard library.workingOn == nil else { return }
            if !library.selection.insert(candidate.id).inserted { library.selection.remove(candidate.id) }
        }
    }

    // MARK: Gone casks

    private var goneCasksCard: some View {
        SectionCard(
            title: "Casks whose apps are gone",
            subtitle: "Homebrew keeps counting a cask as installed after you delete its app by hand. Forgetting it clears Homebrew’s record.",
            symbol: "trash.slash"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button(tools.hasCheckedForGoneCasks ? "Check Again" : "Look for Gone Casks", systemImage: "magnifyingglass") {
                        Task { await tools.findGoneCasks() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(tools.isCheckingForGoneCasks || tools.isForgetting)

                    Button("Forget \(tools.goneCasks.count)…", systemImage: "minus.circle") { confirmingForget = true }
                        .buttonStyle(.bordered)
                        .disabled(tools.goneCasks.isEmpty || tools.isForgetting)

                    if tools.isCheckingForGoneCasks || tools.isForgetting { ProgressView().controlSize(.small) }
                }

                if tools.hasCheckedForGoneCasks, tools.goneCasks.isEmpty {
                    Text("Every installed cask still has its app.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(tools.goneCasks) { cask in
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary)
                        Text(cask.name).font(.subheadline.weight(.semibold))
                        if let version = cask.installedVersion { Text(version).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(cask.appNames.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message = tools.forgetMessage {
                    Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
