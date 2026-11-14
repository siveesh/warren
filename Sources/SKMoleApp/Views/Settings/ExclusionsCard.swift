// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PeelCore
import SwiftUI

/// Settings card for the files, folders and apps Warren must leave alone. Every tool honours it: nothing excluded is
/// listed for removal or moved, and nothing inside an excluded folder is either.
struct ExclusionsCard: View {
    let library: ExclusionsLibrary
    let apps: AppLibrary
    @State private var selectedPaths: Set<URL> = []
    @State private var selectedApps: Set<String> = []
    @State private var refused: [String] = []

    var body: some View {
        SectionCard(
            title: "Exclusions",
            subtitle: "Files, folders and apps Warren never lists for removal and never moves, in every section. Cleanup, Storage, Uninstaller, Orphans, Intel Software and Package Receipts all follow this list.",
            symbol: "hand.raised.square"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if library.exclusions.isUnreadable {
                    problem(
                        "Warren couldn’t read your exclusions",
                        "Until it can, or you start over, Warren removes nothing, because it can’t tell what you asked it to leave alone. Starting over keeps the old file beside a new list.",
                        action: ("Start Over", { Task { await library.startOver() } })
                    )
                }
                if library.couldNotSave {
                    problem(
                        "Your latest change couldn’t be saved",
                        "It stays in force until Warren quits. After that the list is as it was last saved.",
                        action: nil
                    )
                }

                pathList
                Divider()
                appList
            }
        }
        .task {
            await library.loadIfNeeded()
            if apps.apps.isEmpty { await apps.rescan() }
        }
        .alert("That folder can’t be excluded.", isPresented: Binding(get: { !refused.isEmpty }, set: { if !$0 { refused = [] } })) {
            Button("OK") {}
        } message: {
            Text("Excluding a folder that broad would hide almost everything from Warren. Choose the folders inside it that matter to you.\n\n\(refused.joined(separator: "\n"))")
        }
    }

    // MARK: Files and folders

    private var pathList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files and Folders").font(.headline)
            if library.paths.isEmpty {
                emptyNote(library.hasLoaded ? "No file or folder is on this list yet." : "Checking…")
            } else {
                ForEach(library.paths, id: \.self) { path in
                    row(selected: selectedPaths.contains(path)) {
                        AppIconThumbnail(url: path, size: 18, cornerRadius: 4)
                        Text(path.path(percentEncoded: false).abbreviatingHome)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } toggle: {
                        if !selectedPaths.insert(path).inserted { selectedPaths.remove(path) }
                    }
                }
            }
            HStack {
                Button("Add Files or Folders…", systemImage: "plus") { choosePaths() }
                Button("Remove", systemImage: "minus") {
                    let removed = Array(selectedPaths)
                    selectedPaths = []
                    Task { await library.remove(paths: removed) }
                }
                .disabled(selectedPaths.isEmpty)
            }
        }
    }

    // MARK: Apps

    private var appList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps").font(.headline)
            Text("An excluded app still appears in Uninstaller, but Warren won’t offer to remove or reset it, and leaves a folder named after its identifier alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if library.appIdentifiers.isEmpty {
                emptyNote(library.hasLoaded ? "No app is on this list yet." : "Checking…")
            } else {
                ForEach(library.appIdentifiers, id: \.self) { identifier in
                    row(selected: selectedApps.contains(identifier)) {
                        if let app = apps.apps.first(where: { $0.bundleIdentifier == identifier }) {
                            AppIconThumbnail(url: app.url, size: 18, cornerRadius: 4)
                            Text(app.name)
                        } else {
                            Image(systemName: "questionmark.app").foregroundStyle(.secondary)
                        }
                        Text(identifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } toggle: {
                        if !selectedApps.insert(identifier).inserted { selectedApps.remove(identifier) }
                    }
                }
            }
            HStack {
                Menu("Add App…", systemImage: "plus") {
                    ForEach(addableApps, id: \.url) { app in
                        Button(app.name) { add(app) }
                    }
                }
                .disabled(addableApps.isEmpty)
                Button("Remove", systemImage: "minus") {
                    let removed = Array(selectedApps)
                    selectedApps = []
                    Task { await library.remove(bundleIdentifiers: removed) }
                }
                .disabled(selectedApps.isEmpty)
            }
        }
    }

    private var addableApps: [PeelCore.InstalledApp] {
        apps.apps
            .filter { app in
                app.bundleIdentifier.map { !library.exclusions.excludes(bundleIdentifier: $0) } ?? !library.exclusions.excludes(app.url)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: PeelCore.InstalledApp) {
        Task {
            // An app with no identifier is left alone by where it is.
            if let identifier = app.bundleIdentifier {
                await library.add(bundleIdentifier: identifier)
            } else {
                await library.add(paths: [app.url])
            }
        }
    }

    private func choosePaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        let tooBroad = panel.urls.filter { Exclusions.isTooBroad($0) }
        refused = tooBroad.map { $0.path(percentEncoded: false).abbreviatingHome }
        let keeping = panel.urls.filter { url in !tooBroad.contains(url) }
        guard !keeping.isEmpty else { return }
        Task { await library.add(paths: keeping) }
    }

    // MARK: Pieces

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    private func row(selected: Bool, @ViewBuilder content: () -> some View, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 8) { content(); Spacer(minLength: 0) }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
    }

    private func problem(_ title: String, _ detail: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let action { Button(action.0, action: action.1) }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
