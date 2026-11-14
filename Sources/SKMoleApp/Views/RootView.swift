import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage(SidebarPreferences.collapsedGroupsKey) private var collapsedGroupsStored = ""
    @AppStorage(SidebarPreferences.hiddenSectionsKey) private var hiddenSectionsStored = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if model.showFullDiskAccessBanner {
                    permissionsBanner
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppPalette.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await model.prepareMainWindow()
        }
        .task(id: model.selection) {
            await model.prepareSelection()
        }
        .sheet(
            isPresented: Binding(
                get: { model.showOnboarding },
                set: { newValue in
                    if !newValue {
                        model.dismissOnboardingForNow()
                    }
                }
            )
        ) {
            OnboardingView(model: model)
        }
        .onOpenURL { url in
            Task { await model.handleIncomingURL(url) }
        }
        .confirmationDialog(
            "Confirm cleanup",
            isPresented: Binding(
                get: { model.pendingCleanupDeletion != nil },
                set: { if !$0 { model.cancelPendingCleanupDeletion() } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingCleanupDeletion
        ) { pending in
            Button(pending.permanentCount > 0 ? "Clean Up" : "Move to Trash", role: .destructive) {
                Task { await model.confirmPendingCleanupDeletion() }
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingCleanupDeletion()
            }
        } message: { pending in
            Text(pending.message)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        let preferences = SidebarPreferences(collapsedStored: collapsedGroupsStored, hiddenStored: hiddenSectionsStored)

        List(
            selection: Binding<SidebarSection?>(
                get: { model.selection },
                set: { if let section = $0 { model.open(section: section) } }
            )
        ) {
            ForEach(SidebarGroup.allCases) { group in
                let sections = preferences.visibleSections(in: group, selection: model.selection)

                if !sections.isEmpty {
                    Section(
                        group.title,
                        isExpanded: Binding(
                            get: { preferences.isExpanded(group) },
                            set: { expanded in
                                var updated = preferences
                                updated.setExpanded(expanded, for: group)
                                collapsedGroupsStored = updated.collapsedStored
                            }
                        )
                    ) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(section.title, systemImage: section.symbol)
                                    .font(.headline)
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .tag(section)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // A section opened from elsewhere (deep link, menu, Smart Care) must not sit inside a collapsed group.
        .onChange(of: model.selection) { _, section in
            var updated = preferences
            if !updated.isExpanded(section.group) {
                updated.setExpanded(true, for: section.group)
                collapsedGroupsStored = updated.collapsedStored
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "aqi.medium")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                    Text("Warren")
                        .font(.title3.weight(.bold))
                }
                Text("Maintenance with guard rails, previews, and native performance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selection {
        case .dashboard:
            DashboardView(model: model)
        case .updates:
            UpdatesView(model: model)
        case .homebrew:
            HomebrewView(model: model)
        case .github:
            GitHubView(model: model)
        case .relay:
            RelayView(model: model)
        case .fileIntelligence:
            FileIntelligenceView(model: model)
        case .network:
            NetworkInspectorView(model: model)
        case .processes:
            ProcessInspectorView(model: model)
        case .quarantine:
            QuarantineView(model: model)
        case .orphans:
            OrphanedFilesView(model: model)
        case .intel:
            IntelView(model: model)
        case .packages:
            PackageReceiptsView(model: model)
        case .smartCare:
            SmartCareView(model: model)
        case .cleanup:
            CleanupView(model: model)
        case .uninstall:
            UninstallView(model: model)
        case .storage:
            StorageView(model: model)
        case .optimize:
            OptimizeView(model: model)
        case .history:
            RemovalHistoryView(model: model)
        }
    }

    private var permissionsBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppPalette.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Full Disk Access Recommended")
                    .font(.headline)
                Text(model.fullDiskAccessStatus.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                model.openFullDiskAccessSettings()
            }
            .buttonStyle(.borderedProminent)

            Button("Dismiss") {
                model.dismissFullDiskAccessBanner()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }
}
