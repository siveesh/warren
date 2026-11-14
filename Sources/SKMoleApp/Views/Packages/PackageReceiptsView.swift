// SPDX-License-Identifier: GPL-3.0-or-later
import PeelCore
import SwiftUI

/// Installer packages macOS has receipts for: what each one installed, what is still on disk, and forgetting
/// receipts whose software is gone.
struct PackageReceiptsView: View {
    @ObservedObject var model: AppModel
    @State private var showReceiptOnly = false
    @State private var confirmingMove = false
    @State private var confirmingForget = false

    private var library: PackageLibrary { model.packageLibrary }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            listPane
            detailPane
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(28)
        .task {
            if library.receipts == nil { await library.refresh() }
        }
    }

    // MARK: List

    private var visible: [PackageReceipt] {
        library.filtered.filter { !showReceiptOnly || $0.nothingLeftOnDisk || $0.holdsNothingToRemove }
    }

    private var listPane: some View {
        SectionCard(
            title: "Package receipts",
            subtitle: "Every installer package macOS remembers, apart from Apple's own.",
            symbol: "shippingbox"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Search packages", text: Binding(get: { library.search }, set: { library.search = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button("Refresh") { Task { await library.refresh() } }
                        .buttonStyle(.bordered)
                        .disabled(library.isScanning)
                }

                HStack {
                    Toggle("Receipt only (nothing left on disk)", isOn: $showReceiptOnly)
                        .font(.subheadline)
                    Spacer()
                    if library.isScanning { ProgressView().controlSize(.small) }
                }

                if library.couldNotAsk {
                    Text("macOS did not answer for some packages, so the list may be incomplete.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.amber)
                }

                if library.receipts == nil {
                    HStack { ProgressView(); Text("Reading receipts…").foregroundStyle(.secondary) }
                } else if visible.isEmpty {
                    ContentUnavailableView("No Packages", systemImage: "shippingbox", description: Text("No receipts match."))
                        .frame(minHeight: 320)
                } else {
                    List {
                        ForEach(visible) { receipt in
                            Button { library.select(receipt) } label: { receiptRow(receipt) }
                                .buttonStyle(.plain)
                                .listRowBackground(library.selectedID == receipt.id ? AppPalette.accent.opacity(0.16) : Color.clear)
                        }
                    }
                    .frame(minHeight: 420)
                }
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity)
    }

    private func receiptRow(_ receipt: PackageReceipt) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(receipt.name ?? receipt.identifier).font(.headline).lineLimit(1)
                Spacer()
                if receipt.nothingLeftOnDisk || receipt.holdsNothingToRemove {
                    Pill(title: "Receipt only", tint: AppPalette.amber)
                }
            }
            Text([receipt.shownVersion, receipt.installDate.map { "installed \(DateFormatting.relativeString(from: $0))" }]
                .compactMap(\.self).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if receipt.name != nil {
                Text(receipt.identifier).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: Detail

    private var detailPane: some View {
        SectionCard(
            title: "What it installed",
            subtitle: "Files a package put on disk. Items move to the Trash; forgetting a receipt moves only its records.",
            symbol: "doc.text.magnifyingglass"
        ) {
            if let receipt = library.selectedReceipt {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(receipt)

                        if let message = library.resultMessage {
                            Label(message, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(AppPalette.mint)
                        }
                        if let error = library.errorMessage {
                            Text(error).font(.subheadline).foregroundStyle(AppPalette.rose)
                        }

                        if receipt.items.isEmpty {
                            Text(receipt.isFileListKnown
                                 ? "Nothing this package installed is still on disk."
                                 : "The receipt does not list its files.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(receipt.items) { item in itemRow(item, in: receipt) }
                            actionBar(receipt)
                        }

                        Divider()
                        forgetSection(receipt)
                    }
                }
                .frame(minHeight: 480)
            } else {
                ContentUnavailableView("Select a Package", systemImage: "shippingbox", description: Text("Choose a package to see what it installed."))
                    .frame(minHeight: 480)
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity)
    }

    private func header(_ receipt: PackageReceipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(receipt.name ?? receipt.identifier).font(.title2.weight(.bold))
            Text(receipt.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let version = receipt.shownVersion { Pill(title: "Version \(version)", tint: AppPalette.sky) }
                Pill(title: receipt.isInstalledForTheAccount() ? "This account" : "All users", tint: AppPalette.accent)
                if receipt.installedThroughItsScripts { Pill(title: "Installed by scripts", tint: AppPalette.amber) }
            }
            if !receipt.installedApps.isEmpty {
                Text("Installed apps: \(receipt.installedApps.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func itemRow(_ item: PackageReceipt.Item, in receipt: PackageReceipt) -> some View {
        let selectable = library.canSelect(item, in: receipt)

        return HStack(alignment: .top, spacing: 12) {
            SelectionCircleButton(isSelected: library.selection.contains(item.url), accessibilityLabel: "Select \(item.url.lastPathComponent)") {
                library.toggle(item, in: receipt)
            }
            .disabled(!selectable)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(.headline)
                Text(item.url.path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)

                if let refusal = item.refusal {
                    Text(RemovalFailureText.describe(refusal)).font(.caption).foregroundStyle(AppPalette.amber)
                } else if let held = item.heldBack {
                    Text(LeftoverText.heldBack(held)).font(.caption).foregroundStyle(AppPalette.amber)
                } else if item.requiresPrivileges {
                    Text(AdministratorRights.current == .askEachTime
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

            ActionIconButton(symbol: "eye", label: "Reveal") { model.reveal(item.url) }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(library.selection.contains(item.url) ? AppPalette.accent.opacity(0.14) : AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func actionBar(_ receipt: PackageReceipt) -> some View {
        let size = library.selectedSize

        return HStack {
            Text("\(library.selection.count) selected · \(size.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, size.known))))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Recommended") { library.selectRecommended(in: receipt) }.buttonStyle(.bordered)
            Button("All") { library.selectAll(in: receipt) }.buttonStyle(.bordered)
            Button("None") { library.selectNone(in: receipt) }.buttonStyle(.bordered)

            Button { confirmingMove = true } label: { Label("Move to Trash", systemImage: "trash") }
                .buttonStyle(.borderedProminent)
                .disabled(library.selection.isEmpty || library.isWorking)
        }
        .confirmationDialog("Move \(library.selection.count) item\(library.selection.count == 1 ? "" : "s") to the Trash?", isPresented: $confirmingMove, titleVisibility: .visible) {
            Button(library.selectedPrivilegedURLs.isEmpty ? "Move to Trash" : "Approve and Move to Trash", role: .destructive) {
                Task { await library.removeSelectedItems() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(moveMessage)
        }
    }

    private var moveMessage: String {
        var text = "You can put the items back from the Trash. The package's receipt stays."
        let privileged = library.selectedPrivilegedURLs
        if !privileged.isEmpty {
            text += "\n\n\(privileged.count) item\(privileged.count == 1 ? "" : "s") need administrator rights (\(privileged.prefix(5).map(\.lastPathComponent).joined(separator: ", "))). macOS will ask for your password or Touch ID."
        }
        return text
    }

    private func forgetSection(_ receipt: PackageReceipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Forget this receipt").font(.headline)
            Text("Moves the receipt's records to the Trash so macOS stops listing the package. The software itself is not touched.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if library.forgettingNeedsAdministrator(receipt) {
                Text(AdministratorRights.current == .askEachTime
                     ? "This is a system-wide receipt, so macOS will ask for your password or Touch ID."
                     : "This is a system-wide receipt and administrator rights are turned off in Settings.")
                    .font(.caption)
                    .foregroundStyle(AppPalette.amber)
            }

            Button { confirmingForget = true } label: { Label("Forget Receipt", systemImage: "xmark.bin") }
                .buttonStyle(.bordered)
                .disabled(library.isWorking || (library.forgettingNeedsAdministrator(receipt) && AdministratorRights.current == .never))
                .confirmationDialog("Forget \(receipt.name ?? receipt.identifier)?", isPresented: $confirmingForget, titleVisibility: .visible) {
                    Button(library.forgettingNeedsAdministrator(receipt) ? "Approve and Forget" : "Forget", role: .destructive) {
                        Task { await library.forget(receipt) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The receipt's .bom and .plist files move to the Trash. You can put them back from there.")
                }
        }
    }
}
