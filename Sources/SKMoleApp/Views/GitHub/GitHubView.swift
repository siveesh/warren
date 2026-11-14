import AppKit
import SwiftUI

struct GitHubView: View {
    @ObservedObject var model: AppModel
    @State private var tokenInput = ""
    @State private var tokenSaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                developerSection
            }
            .padding(28)
        }
    }

    private var developerSection: some View {
        SectionCard(
            title: "GitHub CLI For Developers",
            subtitle: "Install `gh`, authenticate through your browser, verify the signed-in account, open token pages, and browse repositories owned by that account.",
            symbol: "chevron.left.forwardslash.chevron.right"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.gitHubCLIStatus.summary)
                            .font(.system(size: 26, weight: .bold, design: .rounded))

                        Text(model.gitHubCLIStatus.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let executablePath = model.gitHubCLIStatus.executablePath {
                            Text(executablePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        metricRow(title: "CLI", value: model.gitHubCLIStatus.version ?? "Not installed")
                        metricRow(title: "Signed In", value: model.gitHubCLIStatus.userLogin ?? "No")
                        metricRow(title: "Projects", value: "\(model.gitHubRepositories.count)")
                    }
                }

                if let gitHubCLIError = model.gitHubCLIError {
                    errorBanner(gitHubCLIError)
                }

                HStack(spacing: 12) {
                    if model.gitHubCLIStatus.isInstalled {
                        Button("Authenticate in Terminal") {
                            model.launchGitHubCLILoginInTerminal()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh Status") {
                            Task { await model.refreshGitHubCLI() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.gitHubCLIBusy)

                        Button("Create Personal Access Token") {
                            model.openGitHubPersonalAccessTokenPage()
                        }
                        .buttonStyle(.bordered)

                        Button("Token Docs") {
                            model.openGitHubPersonalAccessTokenDocs()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Install GitHub CLI") {
                            Task { await model.installGitHubCLI() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.homebrewStatus.isInstalled || model.homebrewBusyActionID == "install:gh-cli")

                        Button("Open GitHub CLI") {
                            model.openGitHubCLIHomepage()
                        }
                        .buttonStyle(.bordered)

                        Button("Authentication Guide") {
                            model.openGitHubCLILoginGuide()
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.gitHubCLIBusy || model.homebrewBusyActionID == "install:gh-cli" {
                        ProgressView()
                    }
                }

                if !model.homebrewStatus.isInstalled && !model.gitHubCLIStatus.isInstalled {
                    Text("Install Homebrew first if you want Warren to install GitHub CLI for you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.gitHubCLIStatus.isInstalled {
                    tokenCard
                }

                CommandSnippetCard(title: "Install GitHub CLI", command: GitHubCLIStatus.installCommand)
                CommandSnippetCard(title: "Authenticate", command: GitHubCLIStatus.authCommand)

                if let authStatusOutput = model.gitHubCLIStatus.authStatusOutput, !authStatusOutput.isEmpty {
                    CommandSnippetCard(title: "Authentication status", command: authStatusOutput, copyLabel: "Copy Status")
                }

                if model.gitHubCLIStatus.isAuthenticated {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Repositories owned by the signed-in account")
                            .font(.headline)

                        if model.gitHubRepositories.isEmpty {
                            Text("No repositories were returned for this account yet. Refresh the status after authentication completes in Terminal.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.gitHubRepositories) { repository in
                                repositoryRow(repository)
                            }
                        }
                    }
                }
            }
        }
    }

    private func repositoryRow(_ repository: GitHubRepositorySummary) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(repository.nameWithOwner)
                    .font(.headline)

                if let description = repository.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(repository.updatedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Pill(title: repository.visibility.capitalized, tint: repository.isPrivate ? AppPalette.rose : AppPalette.accent)

            if repository.isFork {
                Pill(title: "Fork", tint: AppPalette.sky)
            }

            if repository.isArchived {
                Pill(title: "Archived", tint: AppPalette.amber)
            }

            Button("Open") {
                model.openGitHubRepository(repository)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Update saved token")
                .font(.headline)
            Text("Paste a new personal access token to replace the one stored in your macOS Keychain. It is handed to GitHub CLI over stdin and is never written to a file or logged.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                SecureField("ghp_… or github_pat_…", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveToken)

                Button("Save to Keychain", action: saveToken)
                    .buttonStyle(.borderedProminent)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || model.gitHubCLIBusy)
            }

            if tokenSaved {
                Label("Token saved to the Keychain.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private func saveToken() {
        let token = tokenInput
        tokenSaved = false
        Task {
            let saved = await model.updateGitHubToken(token)
            if saved {
                tokenInput = ""
                tokenSaved = true
            }
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .frame(width: 190, alignment: .leading)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppPalette.rose)
            )
    }
}
