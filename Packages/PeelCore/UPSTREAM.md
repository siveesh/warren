# Upstream

Vendored from https://github.com/TuguiDragos/Peel (GPL-3.0-or-later) at commit
`094681646d9c0f9fa87fd1ab0c508108262300d8` (Packages/PeelCore: Sources/PeelCore,
Sources/PeelPrivileged and Tests/PeelCoreTests).

Not vendored: `PeelCommandLine`, `PeelLink`, the Peel app, helper, Finder extension
and CLI targets. Tests that import those modules were removed.

Keep edits to vendored files small and listed here so later syncs are a diff
against the commit above.

## Local changes
- `Sources/PeelCore/Removal/RemovalGuard.swift`: refuses anything inside `.git`, `.svn` or `.hg` folders (`isInsideVersionControl`).

Tests removed because they read Peel's repository files (app sources, docs, string
catalogs, helper plist) that do not exist here: AlertDefaultButton, DebugBuild,
DecorativeSymbol, Documentation, HeldBanner, HelperPolicy, LineLength, MotionKind,
OwnUpdates, PackageResolved, PageBinding, ScanAnnouncement, StringCatalog,
TerminalTheme, and `safetyMDCountsEveryPlace` in DesktopWalletTests.
`launchdHasEveryJob` trait copied into `LaunchdJobsTrait.swift` (original lives in
a test file that needs the CLI target).
Also removed (depended on removed tests): SystemSettingsStep, TargetSize, TerminalThemeLedger, PrivateDatabase, InflectionMarkup, LinkedText tests.
- `Support/PeelFolder.swift`: data folder is `Library/Application Support/SK Mole/Engine` instead of `.../Peel`.
- `Sources/PeelPrivileged/ProtectedData.swift`: `aiModelFolders` (local AI model folders) added to `homeTrees`, so every removal path refuses them.
- `Sources/PeelPrivileged/HelperInterface.swift`: Warren's identifiers (`com.siveesh.skmole`, `com.siveesh.skmole.privilegedhelper`), protocol version 24, and `runMaintenanceTask` (DNS flush, local snapshot thinning, daily periodic).
- `Sources/PeelCore/Removal/PrivilegedHelper.swift`: `runMaintenanceTask(_:)` for those tasks.
- `Homebrew/Homebrew.swift`: `install(_:adopting:onOutput:)` (brew install --cask, optionally `--adopt`). `Homebrew/CaskEvidence.swift`: `cask(for:in:)` is public.
