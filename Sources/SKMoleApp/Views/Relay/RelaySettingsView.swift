import RelayAppSupport
import SwiftUI
import RelaySecurity

/// Relay settings: shortcut, variables, security, and data panes.
struct RelaySettingsView: View {
    let environment: RelayEnvironment

    var body: some View {
        TabView {
            ShortcutSettingsView()
                .tabItem { Label("Shortcut", systemImage: "command") }
            CustomVariablesView()
                .tabItem { Label("Variables", systemImage: "dollarsign.circle") }
            SecuritySettingsView()
                .tabItem { Label("Security", systemImage: "lock.shield") }
            DataSettingsView(environment: environment)
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(minHeight: 460)
    }
}

private struct ShortcutSettingsView: View {
    @State private var hotKeyPref = HotKeyPreference.load()

    var body: some View {
        Form {
            Section("Command palette") {
                LabeledContent("Global Shortcut") {
                    HotKeyRecorderView(preference: $hotKeyPref)
                }
                Text("The palette opens from the Warren menu bar companion. Keep the companion enabled in Settings for the shortcut to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Custom Variables

/// Editor for user-defined Relay variables ($NAS, $CurrentProject, etc.).
/// Values are persisted in UserDefaults and injected into VariableResolver at launch.
private struct CustomVariablesView: View {

    @State private var entries: [VarEntry] = CustomVariablesView.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, _ in
                        HStack(spacing: 6) {
                            Text("$").foregroundStyle(.secondary).font(.system(.body, design: .monospaced))
                            TextField("NAME", text: $entries[index].key)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: 130)
                            Text("=").foregroundStyle(.secondary)
                            TextField("value or path", text: $entries[index].value)
                            Button(role: .destructive) {
                                entries.remove(at: index)
                                save()
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        entries.append(VarEntry(key: "", value: ""))
                    } label: {
                        Label("Add Variable", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Custom Variables")
                } footer: {
                    Text("Use **$NAME** in any command, working directory, or environment value. Built-ins like $Desktop and $Clipboard are always available and cannot be overridden here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .onChange(of: entries) { _, _ in save() }

            Divider()
            HStack {
                Spacer()
                Text("Changes apply to new executions immediately.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    // MARK: Persistence

    private static func load() -> [VarEntry] {
        RelayShared.loadCustomVariables().sorted { $0.key < $1.key }.map { VarEntry(key: $0.key, value: $0.value) }
    }

    private func save() {
        var dict: [String: String] = [:]
        for entry in entries where !entry.key.trimmingCharacters(in: .whitespaces).isEmpty {
            dict[entry.key.trimmingCharacters(in: .whitespaces)] = entry.value
        }
        RelayShared.saveCustomVariables(dict)
    }
}

private struct VarEntry: Equatable {
    var key: String
    var value: String
}

private struct SecuritySettingsView: View {
    @State private var model = SecurityModel()

    var body: some View {
        Form {
            Section("Touch ID for sudo") {
                LabeledContent("Touch ID hardware") {
                    RelayStatusPill(ok: model.touchIDHardware,
                               text: model.touchIDHardware ? "Available" : "Not available")
                }
                LabeledContent("sudo configuration") {
                    sudoRelayStatusPill
                }

                if model.touchIDHardware, model.sudoStatus != .enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Relay never changes your sudo configuration. To enable Touch ID for sudo, run this once in Terminal:")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(model.enableGuidanceCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.enableGuidanceCommand, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain)
                            .help("Copy")
                        }
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Section("Administrator operations") {
                Text("Each operation asks for your password or Touch ID through the standard macOS dialog. Only these curated operations are offered here - never arbitrary commands.")
                    .font(.caption).foregroundStyle(.secondary)

                PrivilegedOperationsGrid { op in model.performOperation(op) }

                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refresh() }
    }

    private var sudoRelayStatusPill: some View {
        switch model.sudoStatus {
        case .enabled: return RelayStatusPill(ok: true, text: "Enabled")
        case .notConfigured: return RelayStatusPill(ok: false, text: "Not configured")
        case .unknown: return RelayStatusPill(ok: false, text: "Unknown")
        }
    }
}

private struct RelayStatusPill: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(text)
        }
        .font(.callout)
    }
}

/// Grid showing every curated privileged operation the helper can perform.
private struct PrivilegedOperationsGrid: View {
    let onRun: (PrivilegedOperation) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(PrivilegedOperation.allCases, id: \.self) { op in
                let runnable = op.elevatedShellCommand != nil
                Button { onRun(op) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: op.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(runnable ? .primary : .secondary)
                        Text(op.summary)
                            .font(.caption2)
                            .foregroundStyle(runnable ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(runnable ? "Run: \(op.summary)" : "Add as a command with 'Requires Elevation' to use this operation")
            }
        }
        .padding(.vertical, 4)
    }
}
