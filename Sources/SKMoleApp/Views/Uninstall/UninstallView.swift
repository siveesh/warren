// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// The Uninstaller: the app inventory on the left, the evidence-based removal plan for one app on the right.
struct UninstallView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var filter: AppFilter = .all
    @State private var sort: AppSort = .name
    @State private var checkedURLs: Set<URL> = []
    @State private var isDropTargeted = false
    @State private var confirmingRemoval = false
    @State private var confirmingBulk = false

    private var library: AppLibrary { model.appLibrary }

    enum AppFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case intel = "Intel only"
        case unused = "Unused 90 days"
        case appStore = "App Store"

        var id: String { rawValue }
    }

    enum AppSort: String, CaseIterable, Identifiable {
        case name = "Name"
        case lastOpened = "Last opened"

        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 22) {
            appsPane
            detailPane
        }
        .padding(28)
        .task {
            if library.apps.isEmpty { await model.refreshApplications() }
        }
        .confirmationDialog(
            "Move \(library.selection.count) item\(library.selection.count == 1 ? "" : "s") to the Trash?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(library.mode == .reset ? "Reset" : "Move to Trash", role: .destructive) {
                Task { await library.removeSelection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
        .confirmationDialog(
            "Uninstall \(checkedURLs.count) app\(checkedURLs.count == 1 ? "" : "s")?",
            isPresented: $confirmingBulk,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                let urls = Array(checkedURLs)
                checkedURLs = []
                Task { await library.removeMany(urls) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each app and its recommended leftovers move to the Trash. Anything that needs review is kept. You can put everything back from the Trash.")
        }
    }

    private var removalMessage: String {
        let size = library.selectedSize
        let text = ByteFormatting.format(UInt64(max(0, size.known)))
        return "About \(size.isComplete ? "" : "at least ")\(text) moves to the Trash. You can put it back from there."
    }

    // MARK: App list

    private var filteredApps: [PeelCore.InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast

        let matching = library.apps.filter { app in
            switch filter {
            case .all: true
            case .intel: app.isIntelOnly
            case .unused: (app.lastUsedDate ?? .distantPast) < cutoff && app.isUseRecorded
            case .appStore: app.isFromAppStore
            }
        }.filter { app in
            query.isEmpty
                || app.name.localizedCaseInsensitiveContains(query)
                || (app.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
                || (app.developer?.localizedCaseInsensitiveContains(query) ?? false)
        }

        switch sort {
        case .name:
            return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastOpened:
            return matching.sorted { ($0.lastUsedDate ?? .distantPast) < ($1.lastUsedDate ?? .distantPast) }
        }
    }

    private var filteredTrashed: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filter == .all else { return [] }
        return model.trashedApplications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var appsPane: some View {
        SectionCard(
            title: "Applications",
            subtitle: "Every installed app with its version, architecture and when you last opened it.",
            symbol: "square.grid.2x2"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Search apps", text: $search)
                        .textFieldStyle(.roundedBorder)

                    Button("Refresh") {
                        Task { await model.refreshApplications() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(library.isScanning)
                }

                HStack {
                    Picker("Show", selection: $filter) {
                        ForEach(AppFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()

                    Picker("Sort", selection: $sort) {
                        ForEach(AppSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()

                    Spacer()

                    if library.isScanning { ProgressView().controlSize(.small) }
                }

                if !checkedURLs.isEmpty {
                    HStack {
                        Text("\(checkedURLs.count) checked")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { checkedURLs = [] }
                            .buttonStyle(.bordered)
                        Button {
                            confirmingBulk = true
                        } label: {
                            Label("Uninstall Checked", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(library.isRemoving)
                    }
                }

                if let note = library.scanNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppPalette.amber)
                }

                dropZone

                List {
                    Section("Installed (\(filteredApps.count))") {
                        ForEach(filteredApps) { app in
                            appRow(app)
                        }
                    }

                    if !filteredTrashed.isEmpty {
                        Section("Apps already in the Trash") {
                            ForEach(filteredTrashed) { app in
                                trashedRow(app)
                            }
                        }
                    }
                }
                .frame(minHeight: 420)
            }
        }
        .frame(minWidth: 400)
    }

    private func appRow(_ app: PeelCore.InstalledApp) -> some View {
        HStack(spacing: 10) {
            SelectionCircleButton(
                isSelected: checkedURLs.contains(app.url),
                accessibilityLabel: "Check \(app.name)"
            ) {
                if checkedURLs.contains(app.url) { checkedURLs.remove(app.url) } else { checkedURLs.insert(app.url) }
            }
            .disabled(app.isSystemProtected)

            Button {
                Task { await library.select(url: app.url) }
            } label: {
                HStack(spacing: 10) {
                    AppIconThumbnail(url: app.url, size: 34, cornerRadius: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline)
                        Text(subtitle(for: app))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if app.isIntelOnly {
                        Pill(title: "Intel", tint: AppPalette.amber)
                    } else if app.prefersIntel {
                        Pill(title: "Rosetta", tint: AppPalette.sky)
                    }

                    if app.isSystemProtected {
                        Pill(title: "macOS", tint: AppPalette.rose)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .listRowBackground(library.selectedURL == app.url ? AppPalette.accent.opacity(0.16) : Color.clear)
    }

    private func trashedRow(_ app: InstalledApp) -> some View {
        Button {
            Task { await library.select(url: app.url) }
        } label: {
            HStack(spacing: 10) {
                AppIconThumbnail(url: app.url, size: 34, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text("In the Trash. Review what it left behind.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(library.selectedURL == app.url ? AppPalette.accent.opacity(0.16) : Color.clear)
    }

    private func subtitle(for app: PeelCore.InstalledApp) -> String {
        var parts: [String] = []
        if let version = app.version { parts.append(version) }
        if let date = app.lastUsedDate, app.isUseRecorded {
            parts.append("opened \(DateFormatting.relativeString(from: date))")
        } else if app.isUseRecorded == false {
            parts.append("no open recorded")
        }
        return parts.joined(separator: " · ")
    }

    private var dropZone: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.app")
            Text("Drop an app here to review its removal")
                .font(.subheadline)
        }
        .foregroundStyle(isDropTargeted ? AppPalette.accent : .secondary)
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(isDropTargeted ? AppPalette.accent : Color.secondary.opacity(0.4))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "app" else { return }
                Task { @MainActor in await library.select(url: url) }
            }
            return true
        }
    }

    // MARK: Detail

    private var detailPane: some View {
        SectionCard(
            title: library.mode == .reset ? "Reset plan" : "Removal plan",
            subtitle: "Every file is listed with the reason Warren ties it to the app. Nothing is deleted: items move to the Trash.",
            symbol: "trash.slash"
        ) {
            if let app = library.selectedApp {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: app)
                        messages
                        if library.isPreparing {
                            HStack { ProgressView(); Text("Looking for everything this app left on your Mac…").foregroundStyle(.secondary) }
                        } else if let plan = library.uninstallation, library.mode == .uninstall {
                            uninstallPlan(plan)
                        } else if let plan = library.reset, library.mode == .reset {
                            resetPlan(plan)
                        }
                    }
                }
                .frame(minHeight: 480)
            } else {
                ContentUnavailableView(
                    "Select an App",
                    systemImage: "xmark.app",
                    description: Text("Choose an app to see its files, why each belongs to it, and what is safe to move to the Trash.")
                )
                .frame(minHeight: 480)
            }
        }
        .frame(minWidth: 520)
    }

    @ViewBuilder
    private var messages: some View {
        if let message = library.resultMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(AppPalette.mint)
        }

        if let error = library.errorMessage {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(AppPalette.rose)
        }
    }

    private func header(for app: PeelCore.InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AppIconThumbnail(url: app.url, size: 56, cornerRadius: 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.title2.weight(.bold))
                    Text([app.version.map { "Version \($0)" }, app.developer].compactMap(\.self).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(app.url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                ActionIconButton(symbol: "eye", label: "Reveal \(app.name)") { model.reveal(app.url) }
            }

            HStack(spacing: 8) {
                Pill(title: architectureTitle(app), tint: app.isIntelOnly ? AppPalette.amber : AppPalette.mint)
                if app.prefersIntel { Pill(title: "Runs through Rosetta", tint: AppPalette.sky) }
                if app.isFromAppStore { Pill(title: "App Store", tint: AppPalette.accent) }
                if app.isSystemProtected { Pill(title: "Part of macOS", tint: AppPalette.rose) }
                if !library.runningInstances.isEmpty { Pill(title: "Running", tint: AppPalette.amber) }
                if let date = app.lastUsedDate, app.isUseRecorded {
                    Pill(title: "Opened \(DateFormatting.relativeString(from: date))", tint: AppPalette.sky)
                }
            }

            if library.selectedApp.map({ !library.isInTrash($0) }) ?? true {
                Picker("Mode", selection: Binding(
                    get: { library.mode },
                    set: { newValue in Task { await library.setMode(newValue) } }
                )) {
                    Text("Uninstall").tag(AppLibrary.Mode.uninstall)
                    Text("Reset settings").tag(AppLibrary.Mode.reset)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
        }
    }

    private func architectureTitle(_ app: PeelCore.InstalledApp) -> String {
        if app.isIntelOnly { return "Intel only" }
        if app.architectures.contains(.arm64) && app.architectures.contains(.x86_64) { return "Universal" }
        return "Apple silicon"
    }

    // MARK: Uninstall plan

    @ViewBuilder
    private func uninstallPlan(_ plan: Uninstallation) -> some View {
        if plan.appStays(canUseHelper: false) {
            Label(stayReason(plan), systemImage: "hand.raised")
                .font(.subheadline)
                .foregroundStyle(AppPalette.amber)
        }

        if plan.uninstallsItself != nil {
            Label("This app has its own uninstaller that Warren lets run, so it may remove more than listed here.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        let recommended = plan.scan.leftovers.filter { $0.match.isRecommended && $0.match.heldBack?.cannotBeMoved != true }
        let review = plan.scan.leftovers.filter { !$0.match.isRecommended && $0.match.heldBack?.cannotBeMoved != true }
        let kept = plan.scan.leftovers.filter { $0.match.heldBack?.cannotBeMoved == true }

        VStack(alignment: .leading, spacing: 10) {
            Text("The app")
                .font(.headline)
            itemRow(
                url: plan.app.url,
                title: plan.app.name + ".app",
                detail: "The app itself.",
                size: plan.isAppMeasured ? plan.appSize : nil,
                confidence: nil,
                note: plan.isAppInTheTrash ? "Already in the Trash." : nil,
                selectable: library.selectableURLs.contains(plan.app.url)
            )
        }

        leftoverSection("Recommended leftovers", subtitle: "Certainly or very likely this app's own files.", items: recommended)
        leftoverSection("Review before removing", subtitle: "Only the name or a shared place ties these to the app. Tick what you recognise.", items: review)
        leftoverSection("Kept", subtitle: "Warren will not move these.", items: kept)

        if recommended.isEmpty && review.isEmpty && kept.isEmpty {
            Text("No leftover files were found. Only the app itself is listed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        actionBar(buttonTitle: "Move to Trash")
    }

    private func stayReason(_ plan: Uninstallation) -> String {
        if plan.app.isSystemProtected { return "This app is part of macOS, so Warren leaves it in place." }
        if plan.isExcluded { return "You excluded this app, so Warren leaves it in place." }
        if plan.app.enclosingPackage != nil { return "This app belongs to another package, so Warren leaves it in place." }
        return "Warren leaves this app in place; its files are not offered as leftovers."
    }

    @ViewBuilder
    private func leftoverSection(_ title: String, subtitle: String, items: [Leftover]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)

                ForEach(items) { leftover in
                    itemRow(
                        url: leftover.url,
                        title: leftover.url.lastPathComponent,
                        detail: "\(LeftoverText.kind(leftover.kind)) · \(LeftoverText.why(leftover.match))",
                        size: leftover.isMeasured ? leftover.size : nil,
                        confidence: LeftoverText.confidence(leftover.match),
                        note: leftover.match.heldBack.map(LeftoverText.heldBack),
                        selectable: library.selectableURLs.contains(leftover.url)
                    )
                }
            }
        }
    }

    // MARK: Reset plan

    @ViewBuilder
    private func resetPlan(_ plan: AppReset) -> some View {
        Text("Clears the app's saved state so it starts fresh. Your settings are backed up first, and everything moves to the Trash.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        ForEach(AppReset.Group.allCases, id: \.self) { group in
            let items = plan.items(in: group)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(resetTitle(group)).font(.headline)
                    ForEach(items) { item in
                        itemRow(
                            url: item.url,
                            title: item.url.lastPathComponent,
                            detail: LeftoverText.kind(item.kind),
                            size: item.size,
                            confidence: nil,
                            note: nil,
                            selectable: true
                        )
                    }
                }
            }
        }

        if plan.items.isEmpty {
            Text("There is nothing to reset for this app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Toggle("Also reset this app's privacy permissions", isOn: Binding(get: { library.resetPrivacy }, set: { library.resetPrivacy = $0 }))
            .font(.subheadline)

        actionBar(buttonTitle: "Reset")
    }

    private func resetTitle(_ group: AppReset.Group) -> String {
        switch group {
        case .settings: "Settings and saved state"
        case .webData: "Web data"
        case .appData: "App data"
        }
    }

    // MARK: Rows and actions

    private func itemRow(
        url: URL,
        title: String,
        detail: String,
        size: Int64?,
        confidence: String?,
        note: String?,
        selectable: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SelectionCircleButton(
                isSelected: library.selection.contains(url),
                accessibilityLabel: "Select \(title)"
            ) {
                library.toggle(url)
            }
            .disabled(!selectable)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if let confidence { Pill(title: confidence, tint: confidence == "Certain" ? AppPalette.mint : AppPalette.amber) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note {
                    Text(note).font(.caption).foregroundStyle(AppPalette.amber)
                }
            }

            Spacer()

            Text(size.map { ByteFormatting.format(UInt64(max(0, $0))) } ?? "unknown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ActionIconButton(symbol: "eye", label: "Reveal \(title)") { model.reveal(url) }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(library.selection.contains(url) ? AppPalette.accent.opacity(0.14) : AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func actionBar(buttonTitle: String) -> some View {
        let size = library.selectedSize
        return VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("\(library.selection.count) selected · \(size.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, size.known))))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Recommended") { library.selectRecommended() }.buttonStyle(.bordered)
                Button("All") { library.selectAll() }.buttonStyle(.bordered)
                Button("None") { library.selectNone() }.buttonStyle(.bordered)

                Button {
                    confirmingRemoval = true
                } label: {
                    Label(buttonTitle, systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.selection.isEmpty || library.isRemoving)

                if library.isRemoving { ProgressView().controlSize(.small) }
            }

            if !library.runningInstances.isEmpty {
                Text("The app is running. Warren quits it first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
