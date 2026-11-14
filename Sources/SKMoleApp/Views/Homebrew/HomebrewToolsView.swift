// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// Homebrew maintenance from the engine ported from Peel: installation facts, cleanup with a preview, vulnerability
/// checks, tap repair and a Brewfile.
struct HomebrewToolsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingCleanup = false

    private var tools: HomebrewToolsLibrary { model.homebrewTools }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            installationCard
            cleanupCard
            vulnerabilitiesCard
            maintenanceCard
        }
        .task {
            if !tools.hasLoadedInstallation { await tools.loadInstallation() }
        }
    }

    // MARK: Installation

    private var installationCard: some View {
        SectionCard(
            title: "Installation",
            subtitle: "Which Homebrew this Mac runs and whether this account may change it.",
            symbol: "info.circle"
        ) {
            if let installation = tools.installation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Pill(title: "Homebrew \(installation.version)", tint: AppPalette.accent)
                        Pill(
                            title: installation.mayBeChangedByThisAccount ? "This account can change it" : "Read only for this account",
                            tint: installation.mayBeChangedByThisAccount ? AppPalette.mint : AppPalette.amber
                        )
                        if installation.isIntelOnAppleSilicon {
                            Pill(title: "Intel Homebrew under Rosetta", tint: AppPalette.amber)
                        }
                    }

                    Text(installation.prefix.path).font(.caption.monospaced()).foregroundStyle(.secondary)

                    if installation.isIntelOnAppleSilicon {
                        Text("This Homebrew lives in /usr/local and runs through Rosetta. Packages installed here are Intel builds; a native Homebrew in /opt/homebrew keeps them native.")
                            .font(.caption)
                            .foregroundStyle(AppPalette.amber)
                    }
                }
            } else if tools.hasLoadedInstallation {
                Text("Homebrew was not found.").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    // MARK: Cleanup

    private var cleanupCard: some View {
        SectionCard(
            title: "Cleanup",
            subtitle: "Reclaim space from old versions and downloads. Preview first: Homebrew's dry run says what would go.",
            symbol: "sparkles"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Strength", selection: Binding(get: { tools.tier }, set: { tools.tier = $0 })) {
                    ForEach(HomebrewToolsLibrary.CleanupTier.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(tools.tier.detail).font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Preview Cleanup") { Task { await tools.previewCleanup() } }
                        .buttonStyle(.bordered)
                        .disabled(tools.isPreviewing || tools.isCleaning)

                    Button { confirmingCleanup = true } label: { Label("Run Cleanup", systemImage: "trash") }
                        .buttonStyle(.borderedProminent)
                        .disabled(tools.isCleaning || tools.isPreviewing)

                    if tools.isPreviewing || tools.isCleaning { ProgressView().controlSize(.small) }
                }

                if let preview = tools.preview {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.bytes.map { $0 == 0 ? "Nothing to clean up." : "Would free about \(ByteFormatting.format(UInt64(max(0, $0))))." } ?? "Homebrew's dry run could not be read.")
                            .font(.subheadline.weight(.semibold))

                        if !preview.autoremoved.isEmpty {
                            Text("Would also uninstall formulae nothing needs: \(preview.autoremoved.joined(separator: ", ")).")
                                .font(.caption)
                                .foregroundStyle(AppPalette.amber)
                        }

                        if tools.tier != .standard {
                            Text("The preview shows the standard cleanup. The stronger options remove more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let output = tools.output, !output.isEmpty {
                    Text(output)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppPalette.secondaryCard.opacity(0.7)))
                }

                if let error = tools.errorMessage {
                    Text(error).font(.caption).foregroundStyle(AppPalette.rose)
                }
            }
        }
        .confirmationDialog("Run \(tools.tier.title.lowercased()) cleanup?", isPresented: $confirmingCleanup, titleVisibility: .visible) {
            Button("Run Cleanup", role: .destructive) { Task { await tools.runCleanup() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew deletes what it removes for good; it does not use the Trash. \(tools.tier.detail)")
        }
    }

    // MARK: Vulnerabilities

    private var vulnerabilitiesCard: some View {
        SectionCard(
            title: "Vulnerabilities",
            subtitle: "Checks installed formulae against OSV.dev through `brew vulns`. Formulae whose issues are all patched are left out.",
            symbol: "exclamationmark.shield"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Check Now") { Task { await tools.checkVulnerabilities() } }
                        .buttonStyle(.bordered)
                        .disabled(tools.isCheckingVulnerabilities)
                    if tools.isCheckingVulnerabilities { ProgressView().controlSize(.small) }
                }

                if let report = tools.vulnerabilities {
                    if report.advisories.isEmpty {
                        Label("No open vulnerabilities found.", systemImage: "checkmark.shield")
                            .foregroundStyle(AppPalette.mint)
                    } else {
                        ForEach(report.advisories) { advisory in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(advisory.formula) \(advisory.version)").font(.headline)
                                    Pill(title: severityTitle(advisory.highestSeverity), tint: severityTint(advisory.highestSeverity))
                                }
                                ForEach(advisory.vulnerabilities) { item in
                                    Text("\(item.id): \(item.summary)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppPalette.secondaryCard.opacity(0.7)))
                        }
                    }

                    if !report.skipped.isEmpty {
                        Text("Not checked: \(report.skipped.joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func severityTitle(_ severity: HomebrewVulnerability.Severity) -> String {
        switch severity {
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .unknown: "Unrated"
        }
    }

    private func severityTint(_ severity: HomebrewVulnerability.Severity) -> Color {
        switch severity {
        case .critical, .high: AppPalette.rose
        case .medium: AppPalette.amber
        case .low, .unknown: AppPalette.sky
        }
    }

    // MARK: Maintenance

    private var maintenanceCard: some View {
        SectionCard(
            title: "Tap repair and Brewfile",
            subtitle: "Repair taps that lost links or renamed their branch, and export a Brewfile to set up another Mac.",
            symbol: "wrench.and.screwdriver"
        ) {
            HStack(spacing: 12) {
                Button("Repair Taps") { Task { await tools.repairTaps() } }
                    .buttonStyle(.bordered)
                    .disabled(tools.isRepairing)

                Button("Save Brewfile…") { Task { await saveBrewfile() } }
                    .buttonStyle(.bordered)
                    .disabled(tools.isExporting)

                Button("Copy Brewfile") {
                    Task {
                        if let text = await tools.brewfile() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(tools.isExporting)

                if tools.isRepairing || tools.isExporting { ProgressView().controlSize(.small) }
            }
        }
    }

    @MainActor
    private func saveBrewfile() async {
        guard let text = await tools.brewfile() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Brewfile"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
