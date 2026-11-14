# Warren Help

Warren keeps your Mac tidy and tells you honestly what it is doing. It finds what can be cleaned, removes apps with everything they leave behind, shows where your storage went, manages Homebrew, and watches your system from the menu bar. It never removes anything until you have seen what it is and said yes.

This guide explains every page, button and setting, and walks through the common jobs. Open it any time from **Help > Warren Help** (⌘?). Use the **Contents** button in the toolbar to jump to a section.

## The ideas behind Warren

A few rules apply everywhere, so it helps to know them once.

- **Preview first.** Every page that can remove something shows a list first, with sizes and the reason each item is there. Nothing is selected for you unless Warren is certain.
- **The Trash, not deletion.** Warren moves items to your Trash, so you can put them back. The one exception is the Power user cleanup profile, described below, and items that are already in the Trash.
- **One safety guard.** A single removal engine sits behind every page. It refuses system folders, Keychains, Mail, SSH keys, local AI model folders, Homebrew's own folders, symbolic links and anything on your Exclusions list. A refusal is final: there is no override button.
- **History.** Every move is recorded, so you can undo it from the History page.
- **Honest sizes.** If Warren could not finish measuring a folder in a reasonable time, it shows "at least" a size, or "unknown", never zero.
- **Nothing leaves your Mac.** Warren has no account and sends no data anywhere. The only network use is checking for updates and talking to Homebrew and GitHub when you ask.

## Getting started

When you first open Warren, a short welcome explains permissions. The most useful one is **Full Disk Access**: without it, macOS stops Warren from looking inside some folders, and you will see a banner at the top of the window saying so.

- Choose **Open Settings** on the banner to go to System Settings > Privacy & Security > Full Disk Access, and turn Warren on.
- Choose **Dismiss** to hide the banner. You can bring the reminder back from Settings > Permissions.

Warren works without Full Disk Access, but scans are less complete and sometimes ask for access folder by folder.

The window has a sidebar on the left, grouped into **Overview**, **Apps**, **Storage**, **Developer** and **System**. Click a group's name to collapse or expand it; Warren remembers your choice. Click a page to open it. The main area on the right shows that page.

Many pages have a **Scan** or **Refresh** button at the top. Scanning only reads; it never changes anything.

## Moving around

You can reach every page from the sidebar, the menu bar, the keyboard or a link.

- **Keyboard shortcuts** (press ⌘ with the key): Dashboard 1, Homebrew 2, Network 3, Quarantine 4, Orphans 5, Smart Care 6, Cleanup 7, Uninstaller 8, Storage 9, Optimize 0, Updates U, GitHub G, Relay R, File Intelligence F, Processes P, Intel Software I, Package Receipts K, History H, Developer Cleanup J.
- **Sections menu** in the menu bar lists every page, including pages you hid from the sidebar.
- **Refresh** menu: **Refresh Current Section** (⌘R) rescans the page you are on. **Refresh Menu Bar Summary** (⇧⌘R) updates the menu bar numbers.
- **Quick Actions** menu: **Export Dry Run Report** (⇧⌘E) and shortcuts to Homebrew and other pages.
- **Links**: a link such as `skmole://section/cleanup` opens that page. This is what Shortcuts and Siri use.
- **Shortcuts and Siri**: the action **Open Warren Section** is available in the Shortcuts app and by voice, for example "Open Cleanup in Warren".

## Overview

### Dashboard

The Dashboard is a live view of your Mac. It refreshes every second or two while it is open.

- **Cards at the top** show CPU, memory, disk and network at a glance.
- **CPU History** and **Memory History** are charts of the last few minutes.
- **Network History** shows download and upload speed. **Open Network Inspector** jumps to the Network page.
- **Pressure and Thermal** shows memory pressure (Stable, Warning, Critical) and your Mac's thermal state. Warren reports macOS's own signals rather than guessing.
- **Per-Core CPU** shows every core, which helps spot one busy core hidden in a low overall number.
- **Update Pulse** shows how many updates are waiting. **Open Updates** goes to the Updates page; **Scan Now** checks for new ones.
- **Smart Care** shows an overall score with the top recommendations.
- **Cleanup Outlook** estimates how much space Cleanup could free.
- **Process Inspector** and **Companion** cards link to those pages. The Companion card tells you whether the menu bar companion is running.
- **Top Processes** lists what is using the most CPU and memory right now.

### Smart Care

Smart Care looks across Cleanup, Storage, updates, permissions and your apps and tells you what is worth doing first.

- **Recommended Actions** is a ranked list. Each item says why it matters. Choose an item's button to go straight to the page that fixes it.
- **Refresh Inputs** collects fresh data from the other pages. **Export Dry Run** saves a report of what Warren would do, without doing it.
- **Quick Actions** are shortcuts to the most useful jobs: Refresh All, Check Updates, Orphan Review, File Intelligence, Network Inspector, Process Inspector, Hidden Space, Admin Space, Review Trash Apps and Flush DNS.
- **Export Center** saves reports in several formats (see Exports below).

### Updates

Updates brings App Store apps, apps with their own update feeds, Homebrew packages and GitHub releases into one list.

- **Scan Now** checks every source.
- **Available Updates** lists apps with a newer version. Choose **Update** to let Warren install it when it can (Homebrew and the App Store through `mas`), or **Open** to go to the vendor's page when only the vendor can install it.
- **Manual Review** lists updates where the final step belongs to the vendor or the App Store sign-in.
- **Deferred Updates** are held back until a date you chose. **Ignored Versions** are muted so a version you deliberately skip stops nagging you.
- **Untracked Apps** have no update source Warren can read. Nothing is wrong with them; Warren simply cannot tell whether they are current.
- **Up to Date** lists what was checked and matches.
- **Filters** at the top narrow the list to updates that need action, ones Warren can install, or manual ones.
- **Update Actions** shows the output of recent install attempts.

## Apps

### Uninstaller

The Uninstaller removes an app together with the files it left in your Library, and shows the evidence for every file.

1. Pick an app from the list on the left. Use the search box, the **Show** menu (all apps, App Store, third-party and so on) and the **Sort** menu to find it. You can also drop an app onto the page. **Refresh** rescans your apps.
2. Warren builds a **Removal plan** on the right. The app comes first. Below it, **Recommended leftovers** are files that are certainly or very likely this app's, with a label such as **Certain** or **Likely** and a one-line reason: for example, a folder named after the app's identifier, or a preference file the app wrote.
3. **Review** items are things Warren found but is not sure about. They are never selected for you. Open them with the eye button to look in Finder.
4. Tick what you want gone, then choose **Move to Trash**. Warren quits the app first if it is open.

The **Mode** switch has two settings: **Uninstall** removes the app and its files; **Reset settings** keeps the app but clears its preferences and caches, which helps when an app misbehaves. Reset can also clear the app's privacy permissions if you turn that option on.

Items owned by the system show a lock. If you allow administrator rights (see Settings), selecting them makes Warren ask macOS for your password or Touch ID, then move them through its helper. Without that permission they are listed but cannot be selected.

### Orphans

Orphans are files that belong to apps that are no longer installed.

- **Scan Again** looks across your Library. Results are grouped by the app they came from.
- Each group has a confidence label: **Certain** (the evidence is strong), **Likely** or **Unsure**. Your Cleanup safety profile decides how far Warren goes: Cautious offers only Certain, Balanced adds Likely, Power user offers all.
- **Select Recommended** ticks the items Warren is confident about. **Select All** and **None** do what they say. The eye button reveals an item in Finder.
- The search box filters groups by name.
- Choose **Move to Trash** to remove the selected files. Warren checks again just before moving that no installed app now claims the file.

### Intel Software

Shows apps, plug-ins, drivers and tools that still contain Intel code. On an Apple silicon Mac, Intel-only software needs Rosetta 2.

- The **Rosetta** card says whether Rosetta is installed and explains why it matters.
- Each group lists items by how much trouble they cause: Intel-only items that need Rosetta, items that contain both Intel and Apple silicon code, and so on. Warren reads each file's architecture directly, so it is not guessing from names.
- Use this page to decide what to replace with a native version or remove. To remove an app, use the Uninstaller.

### Package Receipts

When you install software from a `.pkg` installer, macOS keeps a receipt. Receipts remain after you delete the app, and they list files the installer put on your Mac.

- Choose a receipt to see the files it installed, which are still there, and their size. **Recommended**, **All** and **None** tick items quickly, and the eye button reveals one in Finder.
- **Move to Trash** removes the ticked files. Check the list first.
- **Forget Receipt** removes only the receipt, so macOS stops listing the package. The software itself is not touched, and the receipt files go to the Trash so you can put them back.
- Files in system locations need administrator rights; Warren shows **Approve and Move to Trash** or **Approve and Forget** and macOS asks for your password. See Settings > Administrator Rights.

### Quarantine

Apps you download carry a quarantine flag that makes macOS ask "Are you sure you want to open it?" once.

- **Apple quarantine review** lists apps that still have the flag, with their code-signing state.
- Select an app to see the signature, the raw flag and the exact command, then remove the flag only for apps you trust. Warren shows the command before it runs.
- Do not remove the flag for software you do not recognise.

## Storage

### Cleanup

Cleanup finds files macOS and your apps can make again: caches, logs, browser leftovers, old installers and more.

1. Choose **Scan** (or open the page; it scans automatically the first time). Each category is sized.
2. Open a category to see its items. Each has a **Safe** or **Review** label and a reason. Safe items are rebuilt automatically by the app that made them. Review items are things you might want, such as old downloads.
3. Tick items, then choose **Move to Trash** (or **Remove**, depending on your safety profile).

Categories include user caches, sandboxed app caches, browser leftovers, logs, developer caches, Docker, package-manager caches, tool caches, installers, old downloads, duplicates and the Trash.

**Cleanup safety** (Settings > Cleanup Safety) decides how careful Cleanup is:

- **Cautious**: confirms every cleanup and sends everything to the Trash. Offers larger items only.
- **Balanced**: confirms only batches with Review items. Safe caches are removed directly; Review items go to the Trash.
- **Power user**: no confirmation, permanent removal, finds smaller items and more developer caches. Use it only if you are sure.

System folders, Keychains, Mail, SSH keys, local AI models, Homebrew folders and symbolic links are protected in every profile.

#### Duplicate folders and files

The **Duplicate folders and files** card finds identical folders and identical files of at least 100 KB.

- Choose **Find Duplicates…** to open the sheet. Pick the folders to search (Desktop, Documents, Downloads, Pictures, Movies and Music are the default). Warren remembers your choice.
- Each group lists the copies. One copy always stays. Copies that sync through iCloud are listed but locked.
- In the Cautious profile there is no **Select Suggested** button, so you choose every copy yourself. Balanced and Power user can use it.
- Right before moving, Warren reads the bytes again and refuses anything that changed.

### Storage

Storage shows where your space went.

- **Scan Storage** measures your folders. The **Inspection mode** switch chooses what you see: **Visible** (normal folders), **Hidden** (purgeable space and local snapshots) or **Admin** (system-facing places such as virtual memory and shared caches, read only).
- **Usage map** and **Category breakdown** show the largest areas.
- **Large files** lists oversized files and app bundles. Select user files and move them to the Trash; apps go through the Uninstaller.
- **Space map explorer** lets you drill down into the biggest folders with focus modes, and export the filtered tree.

### File Intelligence

File Intelligence tells you what files really are by reading their content, not their name. It uses Google's Magika model if it is installed.

- **Add** files or folders, or drop them on the Targets area. Turn on **Recursive** to include subfolders.
- **Scan** runs the classification. The summary highlights files whose real type differs from their extension, which is often where problems hide.
- Filter the results by type or search by name. Selecting a result shows the raw model guess beside the trusted answer.
- If Magika is missing, the page offers to install it with Homebrew.

## Developer

### Developer Cleanup

Developer Cleanup clears build data and caches that your tools rebuild: Xcode, Swift, npm, Gradle, CocoaPods and others.

It has three views, chosen at the top:

- **Xcode & Tools**: one card per tool (for example Xcode, npm, Claude). Each row is a folder, with a size, a last-used date and a note saying what it is and what you lose by removing it. **Select** menus on each card give quick choices: recommended items, items older than a date, or keep the newest.
- **Simulators**: simulator runtimes Xcode downloaded for iOS, watchOS, tvOS and visionOS. Pick the versions you no longer need. **Delete Unavailable Devices…** removes simulators Xcode can no longer run, and **Delete Selected Runtimes…** removes the runtimes you ticked.
- **Projects**: choose folders where your code lives, and Warren finds build folders inside them (`.build`, `node_modules`, `Pods`, `target`, `__pycache__` and more). It skips anything Git tracks, anything inside `.git`, and any project changed in the last few days.

Nothing is selected for you. If Xcode or Simulator is open, the page asks you to quit it first. **Scan Again** refreshes the list. Archives (`.xcarchive`) are listed individually and are never selected automatically, because they hold the debug symbols you need to read crash reports from shipped builds.

### Homebrew

Homebrew is the package manager for command-line tools and many Mac apps. Warren gives it a visual interface. If Homebrew is not installed, the page offers the official install command; **Install Homebrew** opens it in Terminal.

#### Overview and maintenance

- The header shows your Homebrew version, how many packages are installed, how many are outdated and how many services run. **Refresh Inventory** reloads the lists.
- **Maintenance** has **Update Metadata** (`brew update`), **Upgrade All** (`brew upgrade`), **Cleanup Cellar**, **Autoremove** and **Run Doctor**. Each card has **Run** and **Copy** buttons; Copy puts the exact command on your clipboard.
- **Doctor** results list problems Homebrew found. For paths that Homebrew says are safe to delete, a button moves them aside after you confirm.

#### Installation, Cleanup, Vulnerabilities, Brewfile

- **Installation** shows which Homebrew runs on this Mac and whether your account can change it. It warns when an Intel Homebrew runs under Rosetta.
- **Cleanup** has three strengths: **Standard**, **Older than 30 days** and **Every download**. **Preview Cleanup** runs Homebrew's dry run and lists what would go. **Run Cleanup** does it.
- **Vulnerabilities**: **Check Now** compares installed formulae against the OSV.dev database through `brew vulns`.
- **Tap repair and Brewfile**: **Repair Taps** fixes taps with broken links. **Save Brewfile…** and **Copy Brewfile** export a list of everything installed, so you can set up another Mac.

#### Taps

Taps add packages from other repositories.

- The list shows every tap, with its package counts, source and last update. Official taps are marked **Official**; others are **Trusted** or **Not trusted**.
- To add one, type `user/repo` (for example `siveesh/tap`). Leave **Git URL** empty for GitHub, or enter an https, ssh or git address. Choose **Add Tap**.
- Right after adding, Warren asks whether to trust the tap. Homebrew will not load an outside tap's packages until you trust it, and trusting lets Homebrew run code from that repository. Trust only taps you trust the maintainer of.
- **Trust** and **Untrust** change that at any time. **Remove** deletes the tap's local copy and asks first; Homebrew refuses while something from the tap is installed.

#### Apps you could manage with Homebrew

Some apps you installed by hand also exist as Homebrew casks. Managing them with Homebrew means one command updates them.

- Choose **Find Apps**. Warren lists apps that are not from the App Store, not Apple's and not already managed by Homebrew, and that have a cask. It reports how many it left alone.
- Tick the apps you want, then choose one of two actions.
- **Hand to Homebrew** keeps your copy and its settings, and only lets Homebrew manage it from then on. It works only when your copy is the exact build Homebrew installs; otherwise nothing changes.
- **Replace with Homebrew’s copy** moves your current app to the Trash, then has Homebrew install its own. Your settings and data stay where they are. If Homebrew fails, put the old app back from History.
- Apps marked **Updates itself** have their own updater too, so both may update them.
- Licences: Hand to Homebrew never touches them. Replace keeps licences that live outside the app file (most do), but a licence for an older major version may not work on the newest version, and activation-based apps may ask you to sign in again. Do not replace Adobe, DaVinci Resolve, Final Cut or other version-locked software unless you have the key.
- Warren does not close apps for you. Quit an app before replacing it.

#### Casks whose apps are gone

If you delete an app by hand, Homebrew still counts its cask as installed. **Look for Gone Casks** finds them, and **Forget** moves Homebrew's record to the Trash so the list is correct again. History can put a record back.

#### Installed packages, discovery and services

- **Installed packages** lists everything with filters for **All**, **Formulae**, **Casks** and **Outdated**. Select one to see details, its exact commands and buttons for **Upgrade**, **Reinstall**, **Uninstall** and **Cleanup**.
- **Discover packages** has a search box and a starter list of popular tools. Choose **Install** on a result.
- **Services** lists background services Homebrew manages, with start, stop and restart.
- A log at the bottom shows the output of recent commands.

### GitHub

For developers: install the GitHub command-line tool (`gh`), sign in through your browser, check which account is signed in, open the token pages, and browse the repositories that account owns. Warren never asks for your password; the sign-in happens on GitHub's own page.

### Relay

Relay is a command palette and workflow runner, built into Warren.

- Press **Option+Space** anywhere to open it. You can change that shortcut in Relay's settings. Type to search your commands, then press Return to run one.
- **Commands** are saved shell snippets with variables such as `$SelectedFinderFiles` and `$CurrentFinderFolder`. Create, edit, import and export them in the Relay page.
- **Tasks** chain commands into workflows.
- **History** records what ran and what it returned.
- Commands that need administrator rights are always shown before they run, and never run silently.
- Relay lives in the menu bar too, so you do not need the main window open.

## System

### Network

An on-demand view of who is using your network, in the style of the Bandwhich tool.

- **Interfaces** shows which network interfaces are up and how much they move.
- **Processes** shows which apps own the most connections.
- **Connections** lists each socket with protocol, process and the local and remote address.
- **Remote Hosts** shows the busiest remote addresses.
- **Refresh** captures a new snapshot. The inspector is deliberately on demand and does not watch continuously.

### Processes

A live list of what is running, sorted by CPU, memory or name.

- Use the sort control and the search box to find a process.
- The **Terminate** button (a stop icon) asks a process to close gracefully. Warren only allows this for your own, non-system processes. It never force-kills.

### Optimize

Low-risk refreshes and helper tasks.

- **Refresh and rebuild** has **Reset Quick Look cache**, **Rebuild Launch Services** (fixes a wrong "Open With" list and file associations), **Refresh Finder** and **Refresh Dock**. Each says what will happen before you run it.
- **Privileged helper** is a small background program that Warren installs once, with your approval, for the two jobs that need administrator rights: a fixed list of maintenance tasks and moving system-owned items to your Trash. It runs no arbitrary command, and it answers only Warren, checked by its code signature.
- Choose **Register Helper**. macOS then asks you to allow Warren in System Settings > General > Login Items & Extensions; the button changes to **Open Login Items** to take you there. Turn Warren on, return and choose **Refresh Status**. The status should read **Installed** and **Reachability: ready**. **Re-check Helper** tests the connection. **Unregister Helper** removes it.
- **Admin tasks** (once the helper is ready): **Flush DNS cache**, **Free up purgeable space** (asks macOS to thin local Time Machine snapshots) and **Run daily periodic maintenance**. Each shows what it does and a caution before you run it with **Run Admin Task**.
- **Startup Items** lists launch agents that start with your account. **Disable** turns off a noisy user item. System-wide items are shown for review only, with an eye button to reveal them in Finder.
- **Recent action log** keeps the output of what you ran this session.

### History

Every item Warren moves is listed here.

- **Removals** shows what moved, when, from which page and how big it was. **Refused** shows what Warren declined to move and why.
- **Undo Last Removal** puts the most recent batch back. **Put Back** restores one item, and **Put Back All** restores a whole batch. **Reveal in Trash** shows where an item is, and **Remove From History** deletes only the history line, not the item.
- Items are put back from the Trash. If you have emptied the Trash, the item is gone; Warren says so.
- The search box filters the list. **Refresh** rereads it.
- Items removed with administrator rights appear here too, marked as administrator removals.

## The menu bar companion

Warren Companion is a small second app that lives in the menu bar and keeps working when the main window is closed.

- Click its icon for a panel with CPU, memory, disk, network, battery, the busiest processes and update status.
- The panel has buttons to reopen Warren, jump to a page, open the Relay palette and quit cleanly.
- It can show alerts when a limit is crossed, such as low disk space or high memory use. Tune them in Settings > Companion Alerts.
- It also feeds the widgets (below).
- Turn the companion on or off in Settings > Menu Bar Companion. Turning it on registers it to start at login; macOS may ask you to approve that in Login Items.

## Widgets

Warren has two widgets. Add them from your desktop: right-click the desktop, choose **Edit Widgets**, find **Warren** and drag one in.

- **System Pulse** (small and medium): CPU, memory and disk rings, with network speed, battery and the busiest app in the medium size.
- **Storage** (small): free space on your startup disk.

The widgets read their numbers from Warren Companion, about once a minute. If a widget says it is waiting, make sure the companion is running.

## Settings

Open Settings with **Warren > Settings…** (⌘,).

- **Startup**: choose which page opens first and keep launch light.
- **Update Checks**: how often Warren checks, and which sources (App Store, GitHub, Sparkle feeds, vendors, Homebrew).
- **Administrator Rights**: **Ask me when something needs them** lets you select system-owned items; macOS asks for your password or Touch ID before anything moves. **Never use administrator rights** shows those items but keeps them unselectable.
- **Sidebar**: choose which tools show in the sidebar. Hidden tools stay reachable from the menu bar, the Sections menu and links.
- **Cleanup Safety**: Cautious, Balanced or Power user (see Cleanup).
- **Exclusions**: files, folders and apps Warren never lists and never moves, on every page. Use **Add Files or Folders…**, **Add App…** and **Remove**. Very broad folders such as your whole home folder are refused. If Warren cannot read the list, it removes nothing until you fix it or choose **Start Over**.
- **Menu Bar Companion** and **Companion Alerts**: turn the companion on, choose what the menu bar shows (an icon, or live numbers) and set alert rules.
- **Permissions**: revisit the welcome, Full Disk Access guidance and the state of the helper.
- **Scheduled Maintenance**: while Warren is running, scan and save a report daily or weekly to Documents/Warren Reports.
- **Export Plugins**: formats Warren can save. They load only when used.

## Exports and reports

Warren can save what it finds so you can keep it or share it.

- **Dry run report**: what Warren would clean, in JSON, CSV or text.
- **Inventory**: every installed app, as JSON, CSV or text, plus a **Brewfile** of your Homebrew packages.
- Choose **Export** on Smart Care, or use ⇧⌘E for a dry run report.

## Common tasks

### Free up space safely

1. Open **Storage** and choose **Scan Storage** to see where space went.
2. Open **Cleanup**, scan, and open the biggest categories. Tick Safe items first.
3. Choose **Move to Trash**. Check the result in **History**.
4. Empty the Trash when you are happy.

### Remove an app completely

1. Open **Uninstaller** and select the app.
2. Look at the recommended leftovers and untick anything you want to keep.
3. Choose **Move to Trash**.
4. Later, open **Orphans** to catch anything from apps you removed earlier.

### Clean up after development

1. Open **Developer Cleanup**. Choose **Scan Again**.
2. In **Projects**, add the folders where your code lives.
3. Use each card's **Select** menu, for example "Older than 30 days", then move the selection to the Trash.
4. In **Simulators**, remove runtimes you no longer test on.

### Hand your apps to Homebrew

1. Open **Homebrew** and find **Apps you could manage with Homebrew**.
2. Choose **Find Apps**, tick what you want, then choose **Hand to Homebrew**.
3. For any app that refuses, quit it and use **Replace** if its licence allows.

### Set up the helper

1. Open **Optimize** and choose **Register Helper**.
2. In Login Items & Extensions, turn Warren on.
3. Return, choose **Refresh Status** and confirm **Reachability: ready**.

### Undo a removal

Open **History**, find the item, and choose **Put Back**, or choose **Undo Last Removal**.

## Keeping you safe

- **Always protected**: system folders, Keychains, Mail, SSH keys, local AI model folders, Homebrew folders and symbolic links.
- **Your Exclusions list** is checked on every page before anything moves.
- **Version control**: nothing inside `.git`, `.svn` or `.hg` is touched, and Git-tracked files are never treated as build output.
- **Verification before moving**: Warren checks again right before each move, so a file that changed since the scan is refused.
- **Administrator rights are opt-in** and always shown before they are used.
- **Open apps**: Warren will not replace or remove an app while it is open.

## Troubleshooting

**Warren says it cannot read a folder.** Give Warren Full Disk Access (see Getting started).

**Register Helper says "Operation not permitted".** macOS is already holding a registration that waits for your approval. Choose the button again (it reads Open Login Items) and turn Warren on in Login Items & Extensions.

**The helper says "not answering".** Choose **Re-check Helper**. If that fails, choose **Unregister Helper**, then **Register Helper**, and approve it again.

**A widget says it is waiting.** Open Settings > Menu Bar Companion and make sure the companion is running. Widgets refresh about once a minute.

**An item was refused.** Open History > Refused. Each refusal has the reason in plain words. Refusals protect you and cannot be overridden.

**Hand to Homebrew did nothing.** Your copy is not the exact build Homebrew installs. Quit the app and use Replace, or update the app first and try again.

**A removed item is not in the Trash.** If you emptied the Trash, it is gone for good. Warren cannot restore it. Cleanup in the Power user profile deletes permanently by design.

**Homebrew pages show nothing.** Homebrew may not be installed, or Warren cannot find it. The Homebrew page header says so.

## About, licence and credits

Warren is free software under the GNU General Public License, version 3 or later. It includes code from Peel by Țugui Dragoș-Constantin, also GPL-3.0-or-later. Choose **Warren > About Warren** for the version, credits and contact links. The licence text is in the app's Resources, in the Licenses folder.
