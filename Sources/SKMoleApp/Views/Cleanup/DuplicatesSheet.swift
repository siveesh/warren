// SPDX-License-Identifier: GPL-3.0-or-later
import PeelCore
import SwiftUI

/// Duplicate folders and files, opened from the Cleanup page. One copy of every group always stays.
struct DuplicatesSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    private var library: DuplicatesLibrary { model.duplicatesLibrary }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Duplicates").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    foldersCard
                    if let message = library.resultMessage {
                        Label(message, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(AppPalette.mint)
                    }
                    if let error = library.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(AppPalette.rose)
                    }
                    results
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            if library.selectionCount > 0 { bar }
        }
        .frame(minWidth: 760, minHeight: 640)
        .confirmationDialog("Move \(library.selectionCount) cop\(library.selectionCount == 1 ? "y" : "ies") to the Trash?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { Task { await library.removeSelection() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("About \(ByteFormatting.format(UInt64(max(0, library.selectedSize)))) is freed. Warren compares the bytes again right before each move, and one copy of every group always stays.")
        }
    }

    private var foldersCard: some View {
        SectionCard(
            title: "Folders to search",
            subtitle: "Identical folders and files of at least 100 KB. Library folders, app packages, repositories and media libraries are never searched. Copies that sync through iCloud are listed but never moved.",
            symbol: "folder.badge.questionmark"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(library.folders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text((folder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { library.removeFolder(folder) }
                            .buttonStyle(.borderless).labelStyle(.iconOnly)
                    }
                    .font(.callout)
                }
                ForEach(library.refusedFolders, id: \.self) { name in
                    Text("\(name) can't be searched.").font(.caption).foregroundStyle(AppPalette.amber)
                }
                HStack {
                    Button("Add Folder…", systemImage: "plus") { library.chooseFolders() }
                    Spacer()
                    if library.isScanning {
                        Text(library.progress).font(.caption).foregroundStyle(.secondary)
                        ProgressView().controlSize(.small)
                        Button("Stop") { library.stop() }
                    } else {
                        Button("Find Duplicates") { library.start() }
                            .buttonStyle(.borderedProminent)
                            .disabled(library.folders.isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if let scan = library.scan {
            if scan.exclusionsNotKnown {
                Text("Warren can't read your exclusions, so it read nothing.").foregroundStyle(AppPalette.amber)
            }
            if scan.needsFullDiskAccess {
                Label("Some folders could not be read. Grant Warren Full Disk Access to see them.", systemImage: "lock.shield").font(.caption).foregroundStyle(AppPalette.amber)
            }
            if scan.groups.isEmpty && scan.folderGroups.isEmpty {
                ContentUnavailableView("No Duplicates Found", systemImage: "checkmark.shield")
            } else {
                HStack {
                    Text("Up to \(ByteFormatting.format(UInt64(max(0, scan.reclaimableSize)))) could be freed")
                        .font(.headline)
                    Spacer()
                    if library.canSuggest {
                        Button("Select Suggested") { library.selectSuggested() }
                    } else {
                        Text("Cautious profile: choose each copy yourself.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(scan.folderGroups) { group in folderGroup(group) }
                ForEach(scan.groups) { group in fileGroup(group) }
            }
        }
    }

    private func folderGroup(_ group: DuplicateFolderGroup) -> some View {
        SectionCard(title: "Identical folders", subtitle: "\(group.fileCount) files · \(ByteFormatting.format(UInt64(max(0, group.size)))) each", symbol: "folder.fill.badge.plus") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.folders) { folder in
                    row(
                        path: folder.url.path(percentEncoded: false),
                        detail: nil,
                        isSelected: library.selectedFolders.contains(folder.url),
                        locked: false
                    ) { library.toggle(folder: folder.url) }
                }
            }
        }
    }

    private func fileGroup(_ group: DuplicateGroup) -> some View {
        SectionCard(title: group.files.first?.url.lastPathComponent ?? "Identical files", subtitle: "\(group.files.count) copies · \(ByteFormatting.format(UInt64(max(0, group.size)))) each", symbol: "doc.on.doc") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.files) { file in
                    row(
                        path: file.url.path(percentEncoded: false),
                        detail: file.heldBack.map { LeftoverText.heldBack($0) } ?? file.modificationDate.formatted(date: .abbreviated, time: .omitted),
                        isSelected: library.selectedFiles.contains(file.url),
                        locked: file.heldBack != nil
                    ) { library.toggle(file: file.url) }
                }
            }
        }
    }

    private func row(path: String, detail: String?, isSelected: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: locked ? "lock" : (isSelected ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(isSelected ? AppPalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text((path as NSString).abbreviatingWithTildeInPath).font(.callout).lineLimit(1).truncationMode(.middle)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(8)
            .background(isSelected ? AppPalette.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private var bar: some View {
        HStack {
            Text("\(library.selectionCount) selected · \(ByteFormatting.format(UInt64(max(0, library.selectedSize))))").font(.callout.weight(.medium))
            Spacer()
            Button("Clear") { library.clearSelection() }
            Button("Move to Trash…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(library.isRemoving)
            if library.isRemoving { ProgressView().controlSize(.small) }
        }
        .padding(14)
        .background(.regularMaterial)
    }
}
