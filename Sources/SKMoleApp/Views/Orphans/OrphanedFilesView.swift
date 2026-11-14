// SPDX-License-Identifier: GPL-3.0-or-later
import PeelCore
import SwiftUI

/// Files that apps left behind, grouped by the app they belonged to and rated by how sure Warren is.
struct OrphanedFilesView: View {
    @ObservedObject var model: AppModel
    @State private var confirming = false

    private var library: OrphanLibrary { model.orphanLibrary }
    private var administratorAllowed: Bool { AdministratorRights.current == .askEachTime }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let message = library.resultMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.mint)
                }

                if let error = library.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(AppPalette.rose)
                }

                notices

                if library.scan == nil {
                    HStack { ProgressView(); Text("Comparing your Library with the apps you have installed…").foregroundStyle(.secondary) }
                } else if library.groups.isEmpty {
                    ContentUnavailableView(
                        "No Leftovers Found",
                        systemImage: "checkmark.shield",
                        description: Text("Nothing in your Library looks like it belongs to an app that is gone.")
                    )
                } else {
                    ForEach(library.groups) { group in
                        groupCard(group)
                    }
                }
            }
            .padding(28)
        }
        .safeAreaInset(edge: .bottom) { selectionBar }
        .task {
            if library.scan == nil { await model.refreshOrphanedFiles() }
        }
        .confirmationDialog(
            "Move \(library.selection.count) item\(library.selection.count == 1 ? "" : "s") to the Trash?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(library.selectedPrivilegedURLs.isEmpty ? "Move to Trash" : "Approve and Move to Trash", role: .destructive) {
                Task { await library.removeSelection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let size = library.selectedSize
        var text = "About \(size.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, size.known)))) moves to the Trash. Warren checks again that no installed app owns these files. You can put them back from the Trash."
        let privileged = library.selectedPrivilegedURLs
        if !privileged.isEmpty {
            let names = privileged.prefix(5).map(\.lastPathComponent).joined(separator: ", ")
            text += "\n\n\(privileged.count) item\(privileged.count == 1 ? "" : "s") need administrator rights (\(names)\(privileged.count > 5 ? ", ..." : "")). macOS will ask for your password or Touch ID."
        }
        return text
    }

    private var header: some View {
        SectionCard(
            title: "Orphaned files",
            subtitle: "Leftovers of apps that are no longer installed. Each group shows how sure Warren is and why. Nothing is ever selected for you.",
            symbol: "questionmark.folder"
        ) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ByteFormatting.format(library.movableBytes))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("could be moved now · \(library.groups.count) group\(library.groups.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Search leftovers", text: Binding(get: { library.search }, set: { library.search = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Button("Scan Again") {
                    Task { await model.refreshOrphanedFiles() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isScanning)

                if library.isScanning { ProgressView().controlSize(.large) }
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let scan = library.scan {
            if scan.needsFullDiskAccess {
                Label("Some folders could not be read. Grant Warren Full Disk Access to find every leftover.", systemImage: "lock.shield")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.amber)
            }

            if !scan.appsOnOtherDisks.isEmpty {
                Label("\(scan.appsOnOtherDisks.count) app\(scan.appsOnOtherDisks.count == 1 ? "" : "s") on other disks are treated as installed.", systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scan.otherAccountsMayOwn {
                Label("Other accounts on this Mac may own some of these files.", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !scan.forAnAdministrator.isEmpty {
                Label("\(scan.forAnAdministrator.count) system-level item\(scan.forAnAdministrator.count == 1 ? "" : "s") are left for an administrator to review in Finder.", systemImage: "person.badge.key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Groups

    private func groupCard(_ group: OrphanGroup) -> some View {
        let tint = tint(for: group.confidence.level)

        return SectionCard(
            title: group.title,
            subtitle: group.confidence.reasons.map(OrphanText.reason).joined(separator: " "),
            symbol: "folder.badge.questionmark"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Pill(title: OrphanText.level(group.confidence.level), tint: tint)
                    Text(sizeText(group.total))
                        .font(.headline)
                    if let date = group.lastModified {
                        Text("last written \(DateFormatting.relativeString(from: date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if group.isLeftAlone {
                        Text("Warren leaves these alone").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Select Recommended") { library.selectRecommended(in: group) }
                            .buttonStyle(.bordered)
                            .disabled(group.confidence.level == .unsure)
                        Button("Select All") { library.selectAll(in: group) }
                            .buttonStyle(.bordered)
                        Button("None") { library.deselect(group: group) }
                            .buttonStyle(.bordered)
                    }
                }

                ForEach(group.items) { item in
                    itemRow(item, in: group)
                }
            }
        }
    }

    private func itemRow(_ item: OrphanItem, in group: OrphanGroup) -> some View {
        let selectable = library.canSelect(item, in: group)

        return HStack(alignment: .top, spacing: 12) {
            SelectionCircleButton(
                isSelected: library.selection.contains(item.url),
                accessibilityLabel: "Select \(item.url.lastPathComponent)"
            ) {
                library.toggle(item, in: group)
            }
            .disabled(!selectable)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).font(.headline)
                Text(LeftoverText.kind(item.kind)).font(.caption).foregroundStyle(.secondary)
                Text(item.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let held = item.heldBack {
                    Text(LeftoverText.heldBack(held)).font(.caption).foregroundStyle(AppPalette.amber)
                } else if item.requiresPrivileges {
                    Text(administratorAllowed
                         ? "Needs administrator rights. You will be asked to approve it."
                         : "Needs administrator rights, which are turned off in Settings.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.amber)
                }
            }

            Spacer()

            Text(item.size.map { ByteFormatting.format(UInt64(max(0, $0))) } ?? "unknown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ActionIconButton(symbol: "eye", label: "Reveal \(item.url.lastPathComponent)") { model.reveal(item.url) }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(library.selection.contains(item.url) ? AppPalette.accent.opacity(0.14) : AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func sizeText(_ total: SizeTotal) -> String {
        "\(total.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, total.known))))"
    }

    private func tint(for level: OrphanConfidence.Level) -> Color {
        switch level {
        case .certain: AppPalette.mint
        case .likely: AppPalette.accent
        case .unsure: AppPalette.amber
        }
    }

    // MARK: Selection bar

    @ViewBuilder
    private var selectionBar: some View {
        if !library.selection.isEmpty {
            HStack {
                let size = library.selectedSize
                Text("\(library.selection.count) selected · \(size.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, size.known))))")
                    .font(.headline)

                Spacer()

                Button("Clear") { library.clearSelection() }.buttonStyle(.bordered)

                Button {
                    confirming = true
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isRemoving)

                if library.isRemoving { ProgressView().controlSize(.small) }
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }
}
