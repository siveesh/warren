# Warren

Warren is a native macOS maintenance toolkit inspired by Mole, CleanMyMac, AppCleaner, DaisyDisk, iStat Menus, and Cork. It is designed around a safety-first workflow: preview before action, protect system-critical paths, isolate admin-only work behind a helper, and keep destructive operations tightly scoped.

## Recent release highlights

### v1.1.7

- The menu bar companion now redistributes spare popover height across the metric cards and Top Processes panel, reducing the empty area below the footer
- The adaptive spacing keeps the compact no-scroll companion layout intact on shorter screens while giving the normal popover a more balanced, professional look

### v1.1.6

- The menu bar companion adds a compact Updates card back into the no-scroll popover so update status is visible without reopening the main dashboard
- Metric card headers are tightened so longer labels such as `THERMAL` stay on one line while retaining right-aligned values
- The companion keeps the simplified footer with only Open Warren and the power-icon quit action

### v1.1.5

- The menu bar companion popover has been tightened into a no-scroll compact layout that fits the core status view inside the normal menu bar popover space
- System configuration now renders as one small single-line summary, keeping model, chip, memory, macOS version, and uptime visible without stacked chips
- CPU, memory, network, disk, power, and thermal cards now use smaller top-right values opposite the card label, with shorter card heights and slimmer progress bars
- The companion footer now keeps only the essentials after Top Processes: Open Warren and a compact power icon to quit the companion

### v1.1.4

- Dashboard cards are significantly denser, with smaller metric tiles, tighter panel spacing, reduced typography, slimmer sparklines, compact per-core CPU rows, and smaller top-process cards
- The menu bar companion popover is more compact, with reduced card padding, narrower width, smaller system chips, tighter telemetry cards, and a shorter screen-aware maximum height
- Dashboard grids now fit more cards per row on medium and large windows so monitoring content starts higher and requires less scrolling
- The compact layout keeps the same telemetry, update, Smart Care, and quick-action data while reducing visual footprint for everyday use

### v1.1.3

- The menu bar companion now uses a smaller status-card design with system configuration chips, compact telemetry tiles, update status, and a concise top-process table
- Warren now checks its own GitHub Releases feed during update scans and can download/open the latest release DMG when an update is available
- Monitoring updates are split into a dedicated store so high-frequency dashboard/menu-bar samples no longer invalidate the whole app model
- Update filtering now uses a cached feature store for active, deferred, ignored, manual, and up-to-date buckets instead of recomputing those lists on every view refresh
- Storage drill-down uses one-pass direct-child sizing for folder maps, improving responsiveness on large directory trees

### v1.1.2

- Homebrew detection now re-checks installed state more reliably, tolerates noisy shell environments, and avoids collapsing the whole tab back to `not installed` when follow-up inventory calls misbehave
- Homebrew inventory and Magika folder scans now stream large subprocess output safely, which fixes the long-running inventory hang and improves recursive folder result loading
- Command-backed integrations now use a shared bounded process runner with timeouts, cancellation, and output caps across Homebrew, GitHub CLI, Magika, network inspection, optimization actions, diagnostics, and privileged helper tasks
- File Intelligence resets stale filters when you add fresh targets and gives a clearer empty state when recursion or filters are hiding results
- The menu bar companion now shares the same memory-pressure classifier as the dashboard, uses more conservative pressure thresholds, and relaunches a stale helper automatically after app updates
- Memory Pressure and Thermal alert thresholds now use explicit level pickers in Settings instead of awkward coarse slider behavior

## Included modules

- Dashboard with live CPU, GPU activity, memory, disk, and network telemetry, plus history views and a smoother long-scroll layout
- Homebrew manager for packages, casks, `brew services`, maintenance, doctor follow-up, curated recommendations, and GitHub CLI workflows
- File Intelligence tab powered by optional Magika CLI integration for content-based type detection, recursive folder scans, confidence-fallback review, and extension-mismatch surfacing
- Network inspector for processes, remote hosts, connections, and interfaces
- Process inspector for active process review with safe, user-owned termination only
- Quarantine review tab for quarantined app bundles with explicit `xattr` actions
- Smart Care recommendations across cleanup, storage, permissions, and app health
- Cleanup center for caches, sandbox caches, logs, browser leftovers, developer artifacts, installers, downloads, duplicates, Docker leftovers, and Trash
- App uninstaller with strict/enhanced/deep remnant previews, reset flows, and Trash-app review
- Storage explorer with multi-volume drill-down, focus filters, and large-file actions
- Optimize center for low-risk cache, system-service, and helper-backed admin maintenance actions
- Menu bar companion for compact monitoring, system configuration, top-process visibility, update awareness, and quick actions
- Scheduled dry-run scan/report exports to `Documents/Warren Reports`

## Developer workflows

- Homebrew installation can be launched from Warren without Apple Events automation permission; the app now opens a temporary Terminal `.command` script instead of scripting Terminal directly
- GitHub CLI install/auth flows are surfaced in the Homebrew area, including auth-status refresh, PAT links, and repository listing for the signed-in account
- Homebrew doctor output can surface actionable unexpected-dylib follow-up directly in the UI
- Homebrew inventory loading is hardened so noisy or partial `brew` JSON output does not collapse the whole tab into a decode error
- Magika can be installed from the existing Homebrew workflow, then used inside Warren without turning it into a bundled heavyweight ML runtime
- Process and maintenance actions now emit unified `os.log` entries through clear Warren log categories for Console-based debugging
- Localization groundwork now ships with an initial `en.lproj` bundle scaffold so the app can grow into fuller translation support cleanly

## Safety boundaries

- System-critical folders are blocked from cleanup and uninstall actions
- Protected Apple apps are not removable
- Cleanup, uninstall, quarantine, and developer-tool actions only operate inside curated allow-lists
- Sensitive user paths like keychains, mail data, SSH/config material, and common shell dotfiles are explicitly blocked from destructive actions
- Cleanup removals are intentionally constrained to reviewed locations, while app removal uses Trash-first handling for user-domain remnants
- Destructive file actions revalidate the target identity immediately before moving or removing it, reducing the risk of path swaps between preview and action
- Quarantine review only removes `com.apple.quarantine`; it does not spoof signatures or bypass broader Gatekeeper trust decisions
- Process termination is limited to the current user’s non-system processes and uses a graceful terminate signal instead of a force kill
- The app exposes only low-risk service refresh tasks directly; admin-only tasks are isolated behind a signed helper allow-list with XPC caller validation instead of arbitrary elevated shell execution

## Notes for testers

- The packaged app in `dist/` is ad-hoc signed in this workspace, so the main UI is testable but privileged-helper registration still requires a real Apple signing identity
- Because this workspace build is unsigned for local distribution, macOS may place `Warren.app` in quarantine and show a misleading warning such as `"Warren.app" is damaged and can’t be opened. You should move it to the Trash.` That is a Gatekeeper/quarantine issue rather than actual app corruption. For local testing, you can remove the quarantine attribute with `xattr -d com.apple.quarantine "Warren.app"`.
- Quarantine actions use the system `xattr` tool directly from Warren and do not require Terminal automation permission
- Homebrew install/auth flows should now open Terminal normally without requiring Terminal Apple Events authorization
- File Intelligence remains optional; if Magika is not installed, Warren stays fully usable and simply offers install/open guidance instead of shipping its own model runtime
- Scheduled reports are dry-run exports only; Warren does not schedule unattended deletion
- The DMG includes both `Warren.app` and this `README.md` for distribution

## GitHub-ready layout

- `Sources/` contains the main app, shared helper contract, and privileged helper target
- `Resources/` contains only source assets and bundle templates that can be reproduced locally
- `.github/workflows/ci.yml` runs build, tests, and app bundling on macOS
- `.gitignore` excludes `.build`, `dist`, generated icon outputs, and other machine-local artifacts

## Privileged helper

The helper is packaged as a launch daemon and is intentionally narrow:

- `flushDNSCache`
- `freePurgeableSpace`
- `runPeriodicDaily`

See [`docs/PRIVILEGED_HELPER.md`](docs/PRIVILEGED_HELPER.md) for the design and signing notes.

## Build

For development:

```bash
swift run SKMoleApp
```

To package a standalone `.app` bundle:

```bash
./scripts/build-app.sh
```

The generated app bundle is created in `dist/Warren.app`.

To package a distributable `.dmg`:

```bash
./scripts/build-dmg.sh
```

The generated disk image is created in `dist/Warren-<version>.dmg` and now includes both `Warren.app` and this `README.md`.

For production helper registration, sign with a real Apple identity:

```bash
SKMOLE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```
