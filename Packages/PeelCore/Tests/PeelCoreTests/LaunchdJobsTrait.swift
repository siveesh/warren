import Testing
@testable import PeelCore

/// Says for the test it marks whether launchd has the jobs Peel asks about, since no test loads a job into launchd.
/// (Copied from Peel's `UninstallsItselfTests.swift`, whose other tests need the CLI target.)
struct LaunchdJobs: TestTrait, TestScoping {
    let areLoaded: Bool

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        let areLoaded = areLoaded
        try await LaunchdCleanup.$loadedStandIn.withValue({ _ in areLoaded }) { try await function() }
    }
}

extension Trait where Self == LaunchdJobs {
    static var launchdHasEveryJob: Self { Self(areLoaded: true) }
    static var launchdHasNoJob: Self { Self(areLoaded: false) }
}
