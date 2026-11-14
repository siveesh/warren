// SPDX-License-Identifier: GPL-3.0-or-later
import PeelCore
import SwiftUI

/// Developer files that tools make again, listed one folder at a time so the person picks exactly what goes: each
/// Xcode project's DerivedData, each archive, each Device Support version and build, simulator runtimes, package
/// caches and the build folders inside their projects. Everything goes to the Trash, with a way back in History.
struct DeveloperCleanupView: View {
    @ObservedObject var model: AppModel
    @State private var confirming = false
    @State private var confirmingRuntimes = false
    @State private var confirmingDevices = false

    private var library: DeveloperCleanupLibrary { model.developerCleanupLibrary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                messages
                switch library.pane {
                case .tools: toolsPane
                case .simulators: simulatorsPane
                case .projects: projectsPane
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .safeAreaInset(edge: .bottom) { selectionBar }
        .task { await library.loadIfNeeded() }
        .onChange(of: library.pane) { _, pane in
            Task {
                switch pane {
                case .tools: await library.loadIfNeeded()
                case .simulators: await library.loadRuntimesIfNeeded()
                case .projects: await library.loadProjectsIfNeeded()
                }
            }
        }
        .confirmationDialog(
            "Move \(library.selected.count) item\(library.selected.count == 1 ? "" : "s") to the Trash?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { Task { await library.removeSelection() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let size = library.selectedSize
            Text("About \(size.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, size.known)))) moves to the Trash. Tools make most of this again the next time you use them. You can put items back from History.")
        }
        .confirmationDialog("Delete \(library.selectedRuntimes.count) simulator runtime\(library.selectedRuntimes.count == 1 ? "" : "s")?", isPresented: $confirmingRuntimes, titleVisibility: .visible) {
            Button("Delete Runtimes", role: .destructive) { Task { await library.deleteSelectedRuntimes() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Xcode removes them with `simctl runtime delete`, which does not use the Trash. You can download a runtime again from Xcode Settings.")
        }
        .confirmationDialog("Delete unavailable simulator devices?", isPresented: $confirmingDevices, titleVisibility: .visible) {
            Button("Delete Unavailable Devices", role: .destructive) { Task { await library.deleteUnavailableDevices() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs `xcrun simctl delete unavailable`: only devices whose runtime is gone, which Xcode itself calls unavailable.")
        }
    }

    // MARK: Header

    private var header: some View {
        SectionCard(
            title: "Developer Cleanup",
            subtitle: "Build data, archives, device symbols, simulators and project build folders that your tools make again. Nothing is selected for you; each row says what it is.",
            symbol: "hammer"
        ) {
            HStack(spacing: 14) {
                Picker("View", selection: Binding(get: { library.pane }, set: { library.pane = $0 })) {
                    ForEach(DeveloperCleanupLibrary.Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Button("Scan Again") {
                    Task {
                        switch library.pane {
                        case .tools: await library.rescanTools()
                        case .simulators: await library.loadRuntimes()
                        case .projects: await library.rescanProjects()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isScanning || library.isLoadingRuntimes || library.isScanningProjects)

                if library.isScanning || library.isLoadingRuntimes || library.isScanningProjects { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let message = library.resultMessage {
            Label(message, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(AppPalette.mint)
        }
        if let error = library.errorMessage {
            Text(error).font(.subheadline).foregroundStyle(AppPalette.rose)
        }
    }

    // MARK: Xcode and tools

    @ViewBuilder
    private var toolsPane: some View {
        if library.environments == nil {
            HStack { ProgressView(); Text("Looking for build data, archives and caches…").foregroundStyle(.secondary) }
        } else if library.shownEnvironments.isEmpty {
            ContentUnavailableView("Nothing Found", systemImage: "checkmark.shield", description: Text("No developer folders to clean were found."))
        } else {
            ForEach(library.shownEnvironments) { environment in environmentCard(environment) }
        }
    }

    private func environmentCard(_ environment: DeveloperEnvironment) -> some View {
        let locations = library.locations(of: environment)
        let total = SizeTotal(locations.map(\.size))
        return SectionCard(
            title: environment.name,
            subtitle: "\(locations.count) folder\(locations.count == 1 ? "" : "s") · \(totalText(total))",
            symbol: environment.systemImage
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    selectMenu(environment, locations: locations)
                    if let app = library.runningApp(for: environment) {
                        Label("\(app) is open. Quit it before moving these.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppPalette.amber)
                    }
                    Spacer()
                }
                ForEach(locations) { location in locationRow(location, environmentName: environment.name) }
            }
        }
    }

    private func selectMenu(_ environment: DeveloperEnvironment, locations: [DeveloperEnvironment.Location]) -> some View {
        let kinds = Set(locations.map(\.kind))
        return Menu("Select") {
            Button("Recommended") { library.selectRecommended(in: environment) }
            Divider()
            Button("Older than 30 days") { library.selectOlder(than: 30, kind: nil, in: environment) }
            Button("Older than 90 days") { library.selectOlder(than: 90, kind: nil, in: environment) }
            Button("Older than 180 days") { library.selectOlder(than: 180, kind: nil, in: environment) }
            if kinds.contains(.archives) {
                Divider()
                Button("All archives except the newest 3") { library.keepNewest(3, kind: .archives, in: environment) }
                Button("All archives except the newest 10") { library.keepNewest(10, kind: .archives, in: environment) }
            }
            if kinds.contains(.deviceSupport) {
                Divider()
                Button("Device Support except the newest 3") { library.keepNewest(3, kind: .deviceSupport, in: environment) }
            }
            Divider()
            Button("Clear selection") { library.deselectAll(in: environment) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func locationRow(_ location: DeveloperEnvironment.Location, environmentName: String) -> some View {
        let warning = warningText(for: location, environmentName: environmentName)
        return Button {
            library.toggle(location.url)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: library.isSelected(location.url) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(library.isSelected(location.url) ? AppPalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: location)).font(.callout.weight(.medium))
                    Text(detail(for: location)).font(.caption).foregroundStyle(.secondary)
                    Text(location.url.path(percentEncoded: false).abbreviatingHome)
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    if let warning { Text(warning).font(.caption).foregroundStyle(AppPalette.amber) }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(location.size.map { ByteFormatting.format(UInt64(max(0, $0))) } ?? "Size unknown")
                        .font(.callout.monospacedDigit())
                    if let date = location.lastWritten {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(library.isSelected(location.url) ? AppPalette.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(for location: DeveloperEnvironment.Location) -> String {
        if let workspace = location.workspace { return workspace.name }
        if let project = location.project { return project }
        if location.kind == .archives {
            let name = location.url.deletingPathExtension().lastPathComponent
            return location.archive?.label.map { "\(name) · \($0)" } ?? name
        }
        if location.kind == .deviceSupport {
            return "\(location.url.deletingLastPathComponent().lastPathComponent) · \(location.url.lastPathComponent)"
        }
        return location.url.lastPathComponent
    }

    private func detail(for location: DeveloperEnvironment.Location) -> String {
        if let workspace = location.workspace { return "Build data for \(workspace.name), made again when you build" }
        switch location.kind {
        case .buildData: return "Build data, made again when you build"
        case .downloads: return "Packages, downloaded again when needed"
        case .cache: return "Cache, made again as you use the tool"
        case .logs: return "Logs of what the tool did"
        case .deviceSupport: return "Symbols copied from a device. Xcode copies them again the next time that system version connects."
        case .archives: return "Archive needed to read crash reports of that build. Keep the ones you shipped."
        default: return location.kind.rawValue
        }
    }

    private func warningText(for location: DeveloperEnvironment.Location, environmentName: String) -> String? {
        switch location.keptBecause {
        case nil: return nil
        case .keptByDefault: return "Not recommended: it takes effort to get back, so it is never selected for you."
        case .heldBack(let reason): return LeftoverText.heldBack(reason)
        case .notTheTools: return "Not recommended: nothing shows that \(environmentName) made this folder."
        case .workspaceMayBeInUse:
            return "Not recommended: this workspace was opened in the last week, or Xcode didn’t record when."
        }
    }

    // MARK: Simulators

    @ViewBuilder
    private var simulatorsPane: some View {
        SectionCard(
            title: "Simulator runtimes",
            subtitle: "Runtimes Xcode downloaded for iOS, watchOS, tvOS and visionOS simulators. Pick the versions you no longer need.",
            symbol: "iphone.gen3"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let message = library.simulatorMessage {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
                if library.runtimes == nil {
                    if library.isLoadingRuntimes {
                        HStack { ProgressView(); Text("Asking simctl…").foregroundStyle(.secondary) }
                    } else {
                        Text("Warren could not read the runtimes. Xcode and its command-line tools have to be installed.")
                            .foregroundStyle(.secondary)
                    }
                } else if library.runtimes?.isEmpty == true {
                    Text("No simulator runtimes are installed.").foregroundStyle(.secondary)
                } else {
                    ForEach(library.runtimes ?? []) { runtime in runtimeRow(runtime) }
                }
                HStack {
                    Button("Delete Selected Runtimes…", role: .destructive) { confirmingRuntimes = true }
                        .disabled(library.selectedRuntimes.isEmpty || library.isChangingSimulators)
                    Button("Delete Unavailable Devices…") { confirmingDevices = true }
                        .disabled(library.isChangingSimulators)
                    if library.isChangingSimulators { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private func runtimeRow(_ runtime: SimulatorRuntime) -> some View {
        let isSelected = library.selectedRuntimes.contains(runtime.id)
        return Button {
            if !library.selectedRuntimes.insert(runtime.id).inserted { library.selectedRuntimes.remove(runtime.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? AppPalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runtime.title).font(.callout.weight(.medium))
                    Text("Last used \(runtime.lastUsed)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(runtime.size).font(.callout.monospacedDigit())
            }
            .padding(10)
            .background(isSelected ? AppPalette.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Projects

    @ViewBuilder
    private var projectsPane: some View {
        SectionCard(
            title: "Project folders",
            subtitle: "Warren looks for build folders (.build, node_modules, Pods, target, __pycache__ and more) inside the folders you choose. It skips anything Git tracks, anything inside .git, and any project changed in the last week.",
            symbol: "folder.badge.gearshape"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(library.projectFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder.path(percentEncoded: false).abbreviatingHome).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { Task { await library.removeProjectFolder(folder) } }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                    }
                    .font(.callout)
                }
                Button("Add Project Folder…", systemImage: "plus") { Task { await library.chooseProjectFolders() } }
                ForEach(library.projectNotes, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(AppPalette.amber)
                }
            }
        }

        if library.projectFolders.isEmpty {
            ContentUnavailableView("Choose Your Project Folders", systemImage: "folder.badge.plus", description: Text("Add the folders your code lives in to find build folders worth removing."))
        } else if library.projectGroups == nil {
            HStack { ProgressView(); Text("Searching your projects…").foregroundStyle(.secondary) }
        } else if library.projectGroups?.isEmpty == true {
            ContentUnavailableView("No Build Folders Found", systemImage: "checkmark.shield")
        } else {
            ForEach(library.projectGroups ?? []) { group in
                SectionCard(title: group.name, subtitle: totalText(group.total), symbol: "shippingbox") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(group.artifacts) { artifact in artifactRow(artifact) }
                    }
                }
            }
        }
    }

    private func artifactRow(_ artifact: ProjectArtifact) -> some View {
        Button {
            library.toggle(artifact.url)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: library.isSelected(artifact.url) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(library.isSelected(artifact.url) ? AppPalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(artifact.name).font(.callout.weight(.medium))
                    Text(artifact.tool ?? "Marked as a cache by its tool").font(.caption).foregroundStyle(.secondary)
                    if let warning = artifactWarning(artifact) {
                        Text(warning).font(.caption).foregroundStyle(AppPalette.amber)
                    }
                }
                Spacer(minLength: 12)
                Text(artifact.size.map { ByteFormatting.format(UInt64(max(0, $0))) } ?? "Size unknown")
                    .font(.callout.monospacedDigit())
            }
            .padding(10)
            .background(library.isSelected(artifact.url) ? AppPalette.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func artifactWarning(_ artifact: ProjectArtifact) -> String? {
        switch artifact.keptBecause {
        case nil: nil
        case .heldBack(let reason): LeftoverText.heldBack(reason)
        case .installedPackages: "Not recommended: installed packages are not made again by a build."
        case .genericName: "Not recommended: the name says nothing about which tool made it."
        case .changedRecently: "Not recommended: the project changed in the last week."
        case .lastChangeNotKnown, .lastChangeNotReadInTime: "Not recommended: Warren could not tell when the project last changed."
        }
    }

    // MARK: Selection bar

    @ViewBuilder
    private var selectionBar: some View {
        if !library.selected.isEmpty {
            let size = library.selectedSize
            HStack(spacing: 14) {
                Text("\(library.selected.count) selected · \(size.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, size.known))))")
                    .font(.callout.weight(.medium))
                if let app = library.appToQuit {
                    Label("Quit \(app) first", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(AppPalette.amber)
                }
                Spacer()
                Button("Clear") { library.selected = [] }
                Button("Move to Trash…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.isRemoving || library.appToQuit != nil)
                if library.isRemoving { ProgressView().controlSize(.small) }
            }
            .padding(14)
            .background(.regularMaterial)
        }
    }

    private func totalText(_ total: SizeTotal) -> String {
        "\(total.isComplete ? "" : "at least ")\(ByteFormatting.format(UInt64(max(0, total.known))))"
    }
}

private extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
