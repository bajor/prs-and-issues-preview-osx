import Foundation
import XCTest
@testable import PRsAndIssuesPreview

final class CleanupServiceTests: XCTestCase {

    /// Test directory for cleanup tests
    private let testRoot = "/tmp/claude/pr-review-cleanup-tests"

    func testInitWithCloneRoot() {
        let service = CleanupService(cloneRoot: "/tmp/test", maxAgeDays: 30)
        XCTAssertNotNil(service)
    }

    func testInitFromConfig() {
        let config = Config(
            githubToken: "test",
            githubUsername: "user",
            repos: ["owner/repo"],
            excludedRepos: [],
            tokens: [:],
            cloneRoot: "/tmp/test",
            pollIntervalSeconds: 300,
            ghosttyPath: "/Applications/Ghostty.app",
            nvimPath: "/opt/homebrew/bin/nvim",
            notifications: NotificationConfig()
        )
        let service = CleanupService(config: config)
        XCTAssertNotNil(service)
    }

    func testShouldRunCleanupInitially() throws {
        // Use a completely unique parent directory to avoid shared state
        let uniqueParent = testRoot + "/fresh1-\(UUID().uuidString)"
        let uniqueRoot = uniqueParent + "/repos"
        // Remove any existing state file
        try? FileManager.default.removeItem(atPath: uniqueParent + "/state.json")
        let service = CleanupService(cloneRoot: uniqueRoot, maxAgeDays: 30)
        XCTAssertTrue(service.shouldRunCleanup())
    }

    func testLastCleanupDateInitially() throws {
        // Use a completely unique parent directory to avoid shared state
        let uniqueParent = testRoot + "/fresh2-\(UUID().uuidString)"
        let uniqueRoot = uniqueParent + "/repos"
        // Remove any existing state file
        try? FileManager.default.removeItem(atPath: uniqueParent + "/state.json")
        let service = CleanupService(cloneRoot: uniqueRoot, maxAgeDays: 30)
        XCTAssertNil(service.lastCleanupDate())
    }

    func testPreviewCleanupNonExistent() {
        let service = CleanupService(cloneRoot: testRoot + "/nonexistent", maxAgeDays: 30)
        let result = service.previewCleanup()
        XCTAssertTrue(result.isEmpty)
    }

    func testRunCleanupNonExistent() {
        let service = CleanupService(cloneRoot: testRoot + "/nonexistent2", maxAgeDays: 30)
        let result = service.runCleanup()
        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testRunCleanupUpdatesDate() {
        let service = CleanupService(cloneRoot: testRoot + "/test3", maxAgeDays: 30)
        _ = service.runCleanup()
        XCTAssertNotNil(service.lastCleanupDate())
    }

    func testShouldRunCleanupAfterRecentCleanup() {
        let service = CleanupService(cloneRoot: testRoot + "/test4", maxAgeDays: 30)
        _ = service.runCleanup()
        XCTAssertFalse(service.shouldRunCleanup())
    }
}

final class CleanupResultTests: XCTestCase {

    func testResultEquality() {
        let result1 = CleanupService.CleanupResult(deletedCount: 5, freedBytes: 1000, errors: [])
        let result2 = CleanupService.CleanupResult(deletedCount: 5, freedBytes: 1000, errors: [])
        XCTAssertEqual(result1, result2)
    }

    func testResultInequalityCount() {
        let result1 = CleanupService.CleanupResult(deletedCount: 5, freedBytes: 1000, errors: [])
        let result2 = CleanupService.CleanupResult(deletedCount: 3, freedBytes: 1000, errors: [])
        XCTAssertNotEqual(result1, result2)
    }

    func testFreedMBCalculation() {
        let result = CleanupService.CleanupResult(deletedCount: 1, freedBytes: 1024 * 1024, errors: [])
        XCTAssertEqual(result.freedMB, 1.0)
    }

    func testFreedMBPartial() {
        let result = CleanupService.CleanupResult(deletedCount: 1, freedBytes: 512 * 1024, errors: [])
        XCTAssertEqual(result.freedMB, 0.5)
    }

    func testFreedMBZero() {
        let result = CleanupService.CleanupResult(deletedCount: 0, freedBytes: 0, errors: [])
        XCTAssertEqual(result.freedMB, 0.0)
    }
}
