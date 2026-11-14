// SPDX-License-Identifier: GPL-3.0-or-later
import PeelCore
import SwiftUI

/// What Warren moved to the Trash, with a way back, and what it refused to move.
struct RemovalHistoryView: View {
    @ObservedObject var model: AppModel

    private var library: HistoryLibrary { model.historyLibrary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let message = library.message {
                    Label(message, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(AppPalette.mint)
                }
                if let error = library.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(AppPalette.rose)
                }
                if let problem = library.logProblem {
                    Text(problem).font(.subheadline).foregroundStyle(AppPalette.amber)
                }

                switch library.tab {
                case .removals: removals
                case .refusals: refusals
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .safeAreaInset(edge: .bottom) { selectionBar }
        .task { await library.load() }
    }

    private var header: some View {
        SectionCard(
            title: "History",
            subtitle: "Everything Warren moved to the Trash can be put back from here while it is still in the Trash. Items removed with administrator rights are in your Trash but not listed.",
            symbol: "clock.arrow.circlepath"
        ) {
            HStack(spacing: 14) {
                Picker("History", selection: Binding(get: { library.tab }, set: { library.tab = $0 })) {
                    ForEach(HistoryLibrary.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                TextField("Search", text: Binding(get: { library.search }, set: { library.search = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Spacer()

                if library.tab == .removals {
                    Button {
                        Task { await library.undoLastRemoval() }
                    } label: {
                        Label("Undo Last Removal", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.batches.isEmpty || library.isWorking)
                }

                Button("Refresh") { Task { await library.load() } }
                    .buttonStyle(.bordered)
                    .disabled(library.isLoading)

                if library.isLoading || library.isWorking { ProgressView().controlSize(.small) }
            }
        }
    }

    // MARK: Removals

    @ViewBuilder
    private var removals: some View {
        if library.batches.isEmpty {
            ContentUnavailableView(
                "Nothing Removed Yet",
                systemImage: "tray",
                description: Text("When Warren moves something to the Trash, it is listed here so you can put it back.")
            )
        } else {
            ForEach(library.batches, id: \.id) { batch in
                SectionCard(
                    title: batch.records.count == 1 ? batch.records[0].originalURL.lastPathComponent : "\(batch.records.count) items",
                    subtitle: "\(batch.date.formatted(date: .abbreviated, time: .shortened))\(batch.records.first.map { $0.source.isEmpty ? "" : " · \($0.source)" } ?? "")",
                    symbol: "trash"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            let total = SizeTotal(batch.records.map(\.size))
                            Text("\(total.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, total.known))))")
                                .font(.headline)
                            Spacer()
                            Button("Select") { library.select(batch: batch.records) }
                                .buttonStyle(.bordered)
                            Button("Put Back All") { Task { await library.putBack(batch: batch.records) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(library.isWorking || !batch.records.contains(where: library.canPutBack))
                        }

                        ForEach(batch.records) { record in recordRow(record) }
                    }
                }
            }
        }
    }

    private func recordRow(_ record: RemovalRecord) -> some View {
        let inTrash = library.canPutBack(record)

        return HStack(alignment: .top, spacing: 12) {
            SelectionCircleButton(isSelected: library.selection.contains(record.id), accessibilityLabel: "Select \(record.originalURL.lastPathComponent)") {
                library.toggle(record)
            }
            .disabled(!inTrash)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.originalURL.lastPathComponent).font(.headline)
                Text(record.originalURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(inTrash ? "In the Trash. It can be put back." : "No longer in the Trash, so it cannot be put back.")
                    .font(.caption)
                    .foregroundStyle(inTrash ? Color.secondary : AppPalette.amber)
            }

            Spacer()

            Text(record.size.map { ByteFormatting.format(UInt64(max(0, $0))) } ?? "unknown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button("Put Back") { Task { await library.putBack([record]) } }
                .buttonStyle(.bordered)
                .disabled(!inTrash || library.isWorking)

            Menu {
                Button("Remove From History") { Task { await library.forget([record]) } }
                Button("Reveal in Trash") { if inTrash { model.reveal(record.trashedURL) } }
                    .disabled(!inTrash)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(library.selection.contains(record.id) ? AppPalette.accent.opacity(0.14) : AppPalette.secondaryCard.opacity(0.7))
        )
    }

    // MARK: Refusals

    @ViewBuilder
    private var refusals: some View {
        if library.refusals.isEmpty {
            ContentUnavailableView(
                "Nothing Refused",
                systemImage: "checkmark.shield",
                description: Text("When the removal guard refuses something you asked to move, it is listed here with the reason.")
            )
        } else {
            SectionCard(
                title: "Refused removals",
                subtitle: "Things you asked Warren to move that the guard kept in place.",
                symbol: "hand.raised"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(library.refusals) { refusal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(refusal.url.lastPathComponent).font(.headline)
                            Text(refusal.url.path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            Text(refusal.failureReason.map(RemovalFailureText.describe) ?? refusal.reason)
                                .font(.caption)
                                .foregroundStyle(AppPalette.amber)
                            Text(refusal.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.secondaryCard.opacity(0.7)))
                    }
                }
            }
        }
    }

    // MARK: Selection bar

    @ViewBuilder
    private var selectionBar: some View {
        if !library.selection.isEmpty, library.tab == .removals {
            HStack {
                Text("\(library.selection.count) selected").font(.headline)
                Spacer()
                Button("Clear") { library.clearSelection() }.buttonStyle(.bordered)
                Button("Remove From History") { Task { await library.forget(library.selectedRecords) } }.buttonStyle(.bordered)
                Button {
                    Task { await library.putBackSelection() }
                } label: {
                    Label("Put Back Selected", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isWorking)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }
}
