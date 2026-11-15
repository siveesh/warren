# Lessons Learned

## 2026-11-15 — CI red after raising swift-tools-version to 6.4

**Context:** Runs #13 and #14 failed. The root `Package.swift` and the local `RelayKit` and `PeelCore` packages declared `swift-tools-version: 6.4`, but the `macos-latest` runner only ships Swift 6.3.

**What went wrong:**
- Tools version was ahead of the CI toolchain, so SwiftPM refused to load the package.
- Lowering only the root manifest was not enough. Each local package needed the same change, and this surfaced one CI run at a time.
- Code written against the 6.4 compiler then failed under 6.3: unused `public import`, variable shadowing, a closure capturing its own binding, and a type-checker complexity error.
- With no local 6.3 toolchain, every batch of errors cost a full CI run.

**How it should have been:** The tools version and code should target the lowest toolchain CI and release builds run on. A toolchain bump should land together with the matching CI runner change.

**Key takeaways:**
1. Keep `swift-tools-version` in every manifest (root and `Packages/*`) at or below the CI runner's Swift version. Grep all manifests when changing it.
2. Check the runner's toolchain (the "Show toolchain" step) before adopting newer-compiler features.
3. Fix every error in a CI log before pushing again, since each iteration costs a full run.
4. Avoid closures that capture their own binding and over-complex expressions, which are fragile across compiler versions.

**Outcome:** CI #18 (`4fd51dc`) passed.
