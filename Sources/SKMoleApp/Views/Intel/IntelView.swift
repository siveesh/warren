// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PeelCore
import SwiftUI

/// Software on this Mac that contains Intel code, with what Rosetta means for each kind.
struct IntelView: View {
    @ObservedObject var model: AppModel

    private var library: IntelLibrary { model.intelLibrary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                rosettaCard

                if library.scan == nil {
                    HStack { ProgressView(); Text("Reading architectures…").foregroundStyle(.secondary) }
                } else if library.findings.isEmpty {
                    ContentUnavailableView(
                        "No Intel-Only Software",
                        systemImage: "checkmark.seal",
                        description: Text("Everything Warren could read runs natively on this Mac.")
                    )
                } else {
                    ForEach(IntelFinding.Kind.allCases, id: \.self) { kind in
                        let findings = library.findings(of: kind)
                        if !findings.isEmpty { section(kind, findings) }
                    }
                }

                if let scan = library.scan, scan.needsFullDiskAccess {
                    Label("Some folders could not be read. Grant Warren Full Disk Access for a complete list.", systemImage: "lock.shield")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.amber)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .task {
            if library.scan == nil { await library.rescan() }
        }
    }

    private var header: some View {
        SectionCard(
            title: "Intel software",
            subtitle: "Apps, plug-ins, drivers and tools that still contain Intel code. Warren reads each file's architecture directly.",
            symbol: "cpu"
        ) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(library.findings.count)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("item\(library.findings.count == 1 ? "" : "s") found")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Scan Again") { Task { await library.rescan() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.isScanning)

                if library.isScanning { ProgressView().controlSize(.large) }
            }
        }
    }

    @ViewBuilder
    private var rosettaCard: some View {
        if library.isAppleSilicon {
            SectionCard(
                title: "Rosetta",
                subtitle: "Rosetta 2 lets Intel apps run on Apple silicon. Apple has said it will not last forever, so prefer native versions.",
                symbol: "arrow.triangle.2.circlepath"
            ) {
                HStack(spacing: 12) {
                    Pill(title: library.rosettaInstalled ? "Installed" : "Not installed", tint: library.rosettaInstalled ? AppPalette.mint : AppPalette.amber)

                    if !library.rosettaInstalled {
                        Text(Rosetta.installCommand)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)

                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Rosetta.installCommand, forType: .string)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
            }
        } else {
            SectionCard(
                title: "This is an Intel Mac",
                subtitle: "Nothing here needs translating today. The list shows what will not run on Apple silicon without Rosetta.",
                symbol: "cpu"
            ) { EmptyView() }
        }
    }

    private func section(_ kind: IntelFinding.Kind, _ findings: [IntelFinding]) -> some View {
        SectionCard(
            title: "\(kind.title) (\(findings.count))",
            subtitle: kind.explanation(onAppleSilicon: library.isAppleSilicon),
            symbol: kind.symbol
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(findings) { finding in
                    row(finding)
                }
            }
        }
    }

    private func row(_ finding: IntelFinding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if finding.url.pathExtension.lowercased() == "app" {
                AppIconThumbnail(url: finding.url, size: 34, cornerRadius: 8)
            } else {
                Image(systemName: finding.kind.symbol)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(finding.name).font(.headline)
                    if finding.prefersIntel { Pill(title: "Prefers Intel", tint: AppPalette.amber) }
                }

                if let owner = finding.owner {
                    Text("Belongs to \(owner)").font(.caption).foregroundStyle(.secondary)
                }

                if !finding.backgroundItems.isEmpty {
                    Text("Started by: \(finding.backgroundItems.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(finding.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let size = finding.size {
                Text(ByteFormatting.format(UInt64(max(0, size))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if finding.kind == .app {
                Button("Review in Uninstaller") {
                    model.open(section: .uninstall)
                    Task { await model.appLibrary.select(url: finding.url) }
                }
                .buttonStyle(.bordered)
            }

            ActionIconButton(symbol: "eye", label: "Reveal \(finding.name)") { model.reveal(finding.url) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.secondaryCard.opacity(0.7)))
    }
}
