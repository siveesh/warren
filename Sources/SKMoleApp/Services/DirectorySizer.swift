import Foundation
import PeelCore
import SKMoleShared

actor DirectorySizer {
    private struct SizeCacheEntry: Codable {
        let sizeBytes: UInt64
        let modificationDate: Date?
        let isDirectory: Bool
        let cachedAt: Date?
        let resourceIdentity: String?
        /// "exact" or "atLeast"; entries written before sizes could be incomplete are exact.
        var state: String? = nil
    }

    private let fileManager = FileManager.default
    private let cacheURL = SharedSupportDirectories.fileURL(named: "size-cache.json")
    private let maxCacheEntries = 5_000
    private let maxCacheFileBytes: UInt64 = 8 * 1_024 * 1_024
    private let maxCacheAge: TimeInterval = 6 * 60 * 60
    private let maxDirectChildren = 2_000
    /// How long one folder may be walked before its size is reported as "at least".
    private let walkBudget: TimeInterval = 12

    private var cache: [String: SizeCacheEntry] = [:]
    private var hasLoadedCache = false
    private var saveTask: Task<Void, Never>?

    func invalidate() {
        cache.removeAll()
        hasLoadedCache = true
        saveNow()
    }

    func pruneMissingEntries() {
        loadCacheIfNeeded()
        cache = cache.filter { fileManager.fileExists(atPath: $0.key) }
        scheduleSave()
    }

    /// The size in bytes as far as it is known: the whole size, or what could be counted. Use `measure(of:)` where
    /// the difference matters.
    func size(of url: URL) async -> UInt64 {
        await measure(of: url).bytes
    }

    /// The size of `url` and how sure that is. The walk has a time budget and notes anything it could not read, so a
    /// folder is exact, "at least" or unknown, never silently counted as zero. (`FileSize` in PeelCore also counts
    /// APFS clones once, but is slower; the Uninstaller uses it where that matters.)
    func measure(of url: URL) async -> MeasuredSize {
        loadCacheIfNeeded()
        let normalized = URLPathSafety.standardized(url)
        let key = normalized.path

        if let cached = cache[key], isCacheValid(cached, for: normalized) {
            return MeasuredSize(bytes: cached.sizeBytes, state: cached.state == MeasuredSize.State.atLeast.rawValue ? .atLeast : .exact)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else {
            return .exact(0)
        }

        let measured: MeasuredSize
        if !isDirectory.boolValue {
            measured = .exact(fileSize(of: normalized))
        } else {
            measured = await Self.walkSize(of: normalized, budget: walkBudget)
            // Nothing counted and not even the folder could be opened: that is unknown, not an empty folder.
            if measured.state == .unknown { return .unknown }
        }

        cache[key] = SizeCacheEntry(
            sizeBytes: measured.bytes,
            modificationDate: modificationDate(for: normalized),
            isDirectory: isDirectory.boolValue,
            cachedAt: .now,
            resourceIdentity: resourceIdentity(for: normalized),
            state: measured.state.rawValue
        )
        trimCacheIfNeeded()
        scheduleSave()
        return measured
    }

    /// Measures several folders at once, a few at a time. Each has its own time budget.
    func measureAll(_ urls: [URL], width: Int = 6) async -> [URL: MeasuredSize] {
        var results: [URL: MeasuredSize] = [:]
        var iterator = urls.makeIterator()

        await withTaskGroup(of: (URL, MeasuredSize).self) { group in
            var running = 0
            while running < width, let url = iterator.next() {
                group.addTask { [self] in (url, await measure(of: url)) }
                running += 1
            }

            while let (url, size) = await group.next() {
                results[url] = size
                if let next = iterator.next() {
                    group.addTask { [self] in (next, await measure(of: next)) }
                }
            }
        }

        return results
    }

    func children(of root: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isPackageKey,
                .localizedNameKey
            ],
            options: options.union(.skipsSubdirectoryDescendants),
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var children: [URL] = []
        for case let child as URL in enumerator {
            children.append(child)
            if children.count >= maxDirectChildren || Task.isCancelled {
                break
            }
        }

        return children
    }

    /// Direct children with their sizes as far as they are known (see `sizedChildrenMeasured`).
    func sizedChildren(of root: URL, includeHidden: Bool = false) async -> [(url: URL, sizeBytes: UInt64)] {
        await sizedChildrenMeasured(of: root, includeHidden: includeHidden).map { ($0.url, $0.size.bytes) }
    }

    /// Collects the paths the enumerator could not read.
    private final class UnreadablePaths: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []

        func add(_ path: String) {
            lock.lock()
            paths.append(path)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return paths
        }
    }

    /// Direct children with honest sizes. A child with something unreadable inside is "at least", one that could
    /// not be opened at all is unknown, and when the walk runs out of time the children it did not finish are
    /// "at least": nothing is silently counted as zero.
    func sizedChildrenMeasured(of root: URL, includeHidden: Bool = false) async -> [(url: URL, size: MeasuredSize)] {
        loadCacheIfNeeded()

        let normalizedRoot = URLPathSafety.standardized(root)
        let directChildren = children(of: normalizedRoot, includeHidden: includeHidden)
        guard !directChildren.isEmpty else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]
        var childBytes = Dictionary(uniqueKeysWithValues: directChildren.map { (URLPathSafety.standardized($0).path, UInt64(0)) })
        let childLookup = Set(childBytes.keys)
        var states: [String: MeasuredSize.State] = [:]

        for child in directChildren {
            if Task.isCancelled {
                break
            }

            let values = try? child.resourceValues(forKeys: resourceKeys)
            let isDirectory = values?.isDirectory == true
            let isPackage = values?.isPackage == true
            let path = URLPathSafety.standardized(child).path

            if !isDirectory {
                childBytes[path] = UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
                if values == nil { states[path] = .unknown }
            } else if isPackage {
                let measured = await measure(of: child)
                childBytes[path] = measured.bytes
                if !measured.isExact { states[path] = measured.state }
            }
        }

        let unreadable = UnreadablePaths()
        let rootPath = normalizedRoot.path
        var timedOut = false

        if let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: includeHidden ? [] : [.skipsHiddenFiles],
            errorHandler: { url, _ in
                unreadable.add(URLPathSafety.standardized(url).path)
                return true
            }
        ) {
            let deadline = Date().addingTimeInterval(45)
            var visited = 0

            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled {
                    break
                }

                visited += 1
                if visited % 512 == 0, Date() > deadline {
                    timedOut = true
                    break
                }

                guard let childPath = directChildPath(for: fileURL, rootPath: rootPath),
                      childLookup.contains(childPath),
                      let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                    continue
                }

                if URLPathSafety.standardized(fileURL).path == childPath {
                    if values.isDirectory == true, values.isPackage == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if values.isDirectory == true {
                    if values.isPackage == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                childBytes[childPath, default: 0] += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            }
        }

        // What could not be read marks its child: the child itself unreadable means nothing was counted.
        for failedPath in unreadable.all {
            guard let childPath = directChildPath(for: URL(fileURLWithPath: failedPath), rootPath: rootPath),
                  childLookup.contains(childPath) else { continue }
            states[childPath] = failedPath == childPath && (childBytes[childPath] ?? 0) == 0 ? .unknown : (states[childPath] == .unknown ? .unknown : .atLeast)
        }

        var results: [(url: URL, size: MeasuredSize)] = []
        for child in directChildren {
            let normalized = URLPathSafety.standardized(child)
            let key = normalized.path
            let bytes = childBytes[key] ?? 0
            let state = timedOut && states[key] != .unknown ? MeasuredSize.State.atLeast : (states[key] ?? .exact)
            let size = MeasuredSize(bytes: state == .unknown ? 0 : bytes, state: state)
            results.append((child, size))

            guard size.isKnown else { continue }
            cache[key] = SizeCacheEntry(
                sizeBytes: size.bytes,
                modificationDate: modificationDate(for: normalized),
                isDirectory: isDirectory(at: normalized),
                cachedAt: .now,
                resourceIdentity: resourceIdentity(for: normalized),
                state: size.state.rawValue
            )
        }

        trimCacheIfNeeded()
        scheduleSave()
        return results
    }

    /// Collects what the walk could not read, from the enumerator's error handler.
    private final class WalkProblems: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var rootFailed = false
        let rootPath: String

        init(rootPath: String) { self.rootPath = rootPath }

        func note(_ path: String) {
            lock.lock()
            count += 1
            if path == rootPath { rootFailed = true }
            lock.unlock()
        }

        var summary: (count: Int, rootFailed: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (count, rootFailed)
        }
    }

    @concurrent
    nonisolated private static func walkSize(of url: URL, budget: TimeInterval) async -> MeasuredSize {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        let problems = WalkProblems(rootPath: url.path)

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { failed, _ in
                problems.note(URLPathSafety.standardized(failed).path)
                return true
            }
        ) else {
            return .unknown
        }

        let deadline = Date().addingTimeInterval(budget)
        var total: UInt64 = 0
        var visited = 0
        var timedOut = false

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                timedOut = true
                break
            }

            visited += 1
            if visited % 512 == 0, Date() > deadline {
                timedOut = true
                break
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if values.isDirectory == true {
                continue
            }

            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        let summary = problems.summary
        if summary.rootFailed, total == 0 { return .unknown }
        return (summary.count > 0 || timedOut) ? .atLeast(total) : .exact(total)
    }

    private func calculateSize(of url: URL) -> UInt64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileSize(of: url)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: UInt64 = 0

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                return total
            }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            if values.isDirectory == true {
                continue
            }

            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        return total
    }

    private func fileSize(of url: URL) -> UInt64 {
        if Task.isCancelled {
            return 0
        }

        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }

        return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func directChildPath(for url: URL, rootPath: String) -> String? {
        let path = URLPathSafety.standardized(url).path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard path.hasPrefix(prefix), path != rootPath else {
            return nil
        }

        let relative = path.dropFirst(prefix.count)
        guard let firstComponent = relative.split(separator: "/", maxSplits: 1).first else {
            return nil
        }

        if rootPath == "/" {
            return "/" + String(firstComponent)
        }

        return URL(fileURLWithPath: rootPath).appendingPathComponent(String(firstComponent)).path
    }

    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else {
            return
        }

        hasLoadedCache = true

        if let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           UInt64(size) > maxCacheFileBytes {
            try? fileManager.removeItem(at: cacheURL)
            return
        }

        guard let data = try? Data(contentsOf: cacheURL) else {
            return
        }

        cache = (try? JSONDecoder().decode([String: SizeCacheEntry].self, from: data)) ?? [:]
        trimCacheIfNeeded()
    }

    private func isCacheValid(_ entry: SizeCacheEntry, for url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        if let cachedAt = entry.cachedAt, Date().timeIntervalSince(cachedAt) > maxCacheAge {
            return false
        }

        guard entry.modificationDate == modificationDate(for: url) else {
            return false
        }

        guard let resourceIdentity = entry.resourceIdentity else {
            return false
        }

        return resourceIdentity == self.resourceIdentity(for: url)
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func resourceIdentity(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]) else {
            return nil
        }

        return [
            values.volumeIdentifier.map { String(describing: $0) } ?? "volume:unknown",
            values.fileResourceIdentifier.map { String(describing: $0) } ?? "file:unknown"
        ].joined(separator: "|")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        trimCacheIfNeeded()
        let snapshot = cache
        let destination = cacheURL

        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let encoder = JSONEncoder()
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: destination, options: .atomic)
            }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        trimCacheIfNeeded()
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func trimCacheIfNeeded() {
        guard cache.count > maxCacheEntries else {
            return
        }

        cache = Dictionary(
            uniqueKeysWithValues: cache
                .sorted { left, right in
                    (left.value.modificationDate ?? .distantPast) > (right.value.modificationDate ?? .distantPast)
                }
                .prefix(maxCacheEntries)
                .map { ($0.key, $0.value) }
        )
    }
}
