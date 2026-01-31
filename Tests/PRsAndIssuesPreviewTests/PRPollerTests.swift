import Foundation
import XCTest
@testable import PRsAndIssuesPreview

final class PRPollerTests: XCTestCase {

    /// Create a test config
    private func makeConfig() -> Config {
        Config(
            githubToken: "test-token",
            githubUsername: "testuser",
            repos: ["owner/repo"],
            tokens: [:],
            cloneRoot: "/tmp/test",
            pollIntervalSeconds: 60,
            ghosttyPath: "/Applications/Ghostty.app",
            nvimPath: "/opt/homebrew/bin/nvim",
            notifications: NotificationConfig()
        )
    }

    func testInitialization() {
        let config = makeConfig()
        let poller = PRPoller(config: config)

        XCTAssertFalse(poller.isPolling)
    }

    func testInitialPollingState() {
        let config = makeConfig()
        let poller = PRPoller(config: config)

        XCTAssertFalse(poller.isPolling)
    }

    func testClearState() {
        let config = makeConfig()
        let poller = PRPoller(config: config)

        // This should not throw
        poller.clearState()
        XCTAssertFalse(poller.isPolling)
    }

    func testStopPollingWhenNotPolling() {
        let config = makeConfig()
        let poller = PRPoller(config: config)

        // Should not throw
        poller.stopPolling()
        XCTAssertFalse(poller.isPolling)
    }
}

final class PRPollerPRChangeTests: XCTestCase {

    func testPrChangeNewPREquality() throws {
        let pr = try makePullRequest(number: 1)
        let change1 = PRPoller.PRChange(pr: pr, repo: "owner/repo", changeType: .newPR)
        let change2 = PRPoller.PRChange(pr: pr, repo: "owner/repo", changeType: .newPR)

        XCTAssertEqual(change1, change2)
    }

    func testPrChangeNewCommitsEquality() throws {
        let pr = try makePullRequest(number: 1)
        let change1 = PRPoller.PRChange(pr: pr, repo: "owner/repo", changeType: .newCommits(oldSHA: "abc", newSHA: "def"))
        let change2 = PRPoller.PRChange(pr: pr, repo: "owner/repo", changeType: .newCommits(oldSHA: "abc", newSHA: "def"))

        XCTAssertEqual(change1, change2)
    }

    func testPrChangeInequalityDifferentType() throws {
        let pr = try makePullRequest(number: 1)
        let change1 = PRPoller.PRChange(pr: pr, repo: "owner/repo", changeType: .newPR)
        let change2 = PRPoller.PRChange(pr: pr, repo: "owner/repo", changeType: .newComments(count: 5))

        XCTAssertNotEqual(change1, change2)
    }

    func testPrChangeInequalityDifferentRepo() throws {
        let pr = try makePullRequest(number: 1)
        let change1 = PRPoller.PRChange(pr: pr, repo: "owner/repo1", changeType: .newPR)
        let change2 = PRPoller.PRChange(pr: pr, repo: "owner/repo2", changeType: .newPR)

        XCTAssertNotEqual(change1, change2)
    }

    func testChangeTypeNewCommentsCount() {
        let changeType = PRPoller.PRChange.ChangeType.newComments(count: 10)
        if case let .newComments(count) = changeType {
            XCTAssertEqual(count, 10)
        } else {
            XCTFail("Expected newComments")
        }
    }

    func testChangeTypeStatusChanged() {
        let changeType = PRPoller.PRChange.ChangeType.statusChanged(from: "open", to: "merged")
        if case let .statusChanged(from, to) = changeType {
            XCTAssertEqual(from, "open")
            XCTAssertEqual(to, "merged")
        } else {
            XCTFail("Expected statusChanged")
        }
    }

    /// Helper to create a test PullRequest by decoding JSON
    private func makePullRequest(number: Int) throws -> PullRequest {
        let json = """
        {
            "id": \(number),
            "number": \(number),
            "title": "Test PR",
            "body": "Test body",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/\(number)",
            "user": {
                "id": 1,
                "login": "testuser",
                "avatar_url": "https://example.com/avatar.png"
            },
            "head": {
                "ref": "feature-branch",
                "sha": "abc123"
            },
            "base": {
                "ref": "main",
                "sha": "def456"
            },
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PullRequest.self, from: json.data(using: .utf8)!)
    }
}

// MARK: - PRPoller Behavior Tests

final class PRPollerBehaviorTests: XCTestCase {

    /// Create a test config
    private func makeConfig(
        repos: [String] = ["owner/repo"],
        username: String = "testuser",
        pollInterval: Int = 60
    ) -> Config {
        Config(
            githubToken: "test-token",
            githubUsername: username,
            repos: repos,
            tokens: [:],
            cloneRoot: "/tmp/test",
            pollIntervalSeconds: pollInterval,
            ghosttyPath: "/Applications/Ghostty.app",
            nvimPath: "/opt/homebrew/bin/nvim",
            notifications: NotificationConfig()
        )
    }

    func testStartPollingSetsIsPolling() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        // Need to handle the fact that startPolling triggers an immediate poll
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: "[]")
        }

        poller.startPolling { _ in }

        // Give time for async to kick in
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(poller.isPolling)

        poller.stopPolling()
    }

    func testStopPollingSetsIsPollingFalse() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: "[]")
        }

        poller.startPolling { _ in }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(poller.isPolling)

        poller.stopPolling()

        // Give time for stop to process
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(poller.isPolling)
    }

    func testStartPollingIgnoresDuplicates() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        let callCount = SendableBox(0)

        MockURLProtocol.requestHandler = { request in
            callCount.value += 1
            return MockURLProtocol.successResponse(for: request, jsonString: "[]")
        }

        poller.startPolling { _ in }
        poller.startPolling { _ in } // Should be ignored
        poller.startPolling { _ in } // Should be ignored

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should only poll once on start
        XCTAssertEqual(callCount.value, 1)

        poller.stopPolling()
    }

    func testPollNowTriggersImmediatePoll() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        let callCount = SendableBox(0)

        MockURLProtocol.requestHandler = { request in
            callCount.value += 1
            return MockURLProtocol.successResponse(for: request, jsonString: "[]")
        }

        await poller.pollNow()
        await poller.pollNow()

        XCTAssertEqual(callCount.value, 2)
    }

    func testPollDetectsNewPRs() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        let prJson = """
        [{
            "id": 1,
            "number": 42,
            "title": "New PR",
            "body": "Body",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/42",
            "user": {"id": 1, "login": "otheruser", "avatar_url": null},
            "head": {"ref": "feature", "sha": "abc123"},
            "base": {"ref": "main", "sha": "def456"},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }]
        """

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: prJson)
        }

        let detectedChanges = SendableBox<[PRPoller.PRChange]>([])
        poller.startPolling { changes in
            detectedChanges.value = changes
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(detectedChanges.value.count, 1)
        if let change = detectedChanges.value.first {
            XCTAssertEqual(change.pr.number, 42)
            if case .newPR = change.changeType {
                // Expected
            } else {
                XCTFail("Expected newPR change type")
            }
        }

        poller.stopPolling()
    }

    func testPollDetectsNewCommits() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        let pollCount = SendableBox(0)
        MockURLProtocol.requestHandler = { request in
            pollCount.value += 1
            let sha = pollCount.value == 1 ? "abc123" : "xyz789" // Different SHA on second poll
            let prJson = """
            [{
                "id": 1,
                "number": 42,
                "title": "PR",
                "body": "Body",
                "state": "open",
                "html_url": "https://github.com/owner/repo/pull/42",
                "user": {"id": 1, "login": "otheruser", "avatar_url": null},
                "head": {"ref": "feature", "sha": "\(sha)"},
                "base": {"ref": "main", "sha": "def456"},
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:00Z"
            }]
            """
            return MockURLProtocol.successResponse(for: request, jsonString: prJson)
        }

        let allChanges = SendableBox<[[PRPoller.PRChange]]>([])
        poller.startPolling { changes in
            allChanges.value.append(changes)
        }

        // Wait for first poll
        try await Task.sleep(nanoseconds: 200_000_000)

        // Manually poll again to detect changes
        await poller.pollNow()

        try await Task.sleep(nanoseconds: 100_000_000)

        // First poll should detect newPR, second should detect newCommits
        XCTAssertGreaterThanOrEqual(allChanges.value.count, 2)
        if allChanges.value.count >= 2 {
            // Second poll should show new commits
            let secondPollChanges = allChanges.value[1]
            if let change = secondPollChanges.first {
                if case let .newCommits(oldSHA, newSHA) = change.changeType {
                    XCTAssertEqual(oldSHA, "abc123")
                    XCTAssertEqual(newSHA, "xyz789")
                } else {
                    XCTFail("Expected newCommits change type")
                }
            }
        }

        poller.stopPolling()
    }

    func testPollFiltersOwnPRs() async throws {
        let config = makeConfig(username: "myuser")
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        // PR is authored by "myuser", which matches config username
        let prJson = """
        [{
            "id": 1,
            "number": 42,
            "title": "My own PR",
            "body": "Body",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/42",
            "user": {"id": 1, "login": "myuser", "avatar_url": null},
            "head": {"ref": "feature", "sha": "abc123"},
            "base": {"ref": "main", "sha": "def456"},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }]
        """

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: prJson)
        }

        let detectedChanges = SendableBox<[PRPoller.PRChange]>([])
        poller.startPolling { changes in
            detectedChanges.value = changes
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should be empty because PR author matches username
        XCTAssertTrue(detectedChanges.value.isEmpty)

        poller.stopPolling()
    }

    func testClearStateResetsTracking() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        let prJson = """
        [{
            "id": 1,
            "number": 42,
            "title": "PR",
            "body": "Body",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/42",
            "user": {"id": 1, "login": "otheruser", "avatar_url": null},
            "head": {"ref": "feature", "sha": "abc123"},
            "base": {"ref": "main", "sha": "def456"},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }]
        """

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: prJson)
        }

        let changeCount = SendableBox(0)
        poller.startPolling { changes in
            changeCount.value += changes.count
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should have detected 1 new PR
        XCTAssertEqual(changeCount.value, 1)

        // Clear state
        poller.clearState()

        // Poll again - should detect same PR as new again
        await poller.pollNow()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Should have detected it again after clear
        XCTAssertEqual(changeCount.value, 2)

        poller.stopPolling()
    }

    func testPollContinuesOnError() async throws {
        let config = makeConfig(repos: ["owner/repo1", "owner/repo2"])
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("repo1") == true {
                // First repo fails
                return MockURLProtocol.errorResponse(for: request, statusCode: 500, message: "Server error")
            } else {
                // Second repo succeeds
                let prJson = """
                [{
                    "id": 1,
                    "number": 42,
                    "title": "PR from repo2",
                    "body": "Body",
                    "state": "open",
                    "html_url": "https://github.com/owner/repo2/pull/42",
                    "user": {"id": 1, "login": "otheruser", "avatar_url": null},
                    "head": {"ref": "feature", "sha": "abc123"},
                    "base": {"ref": "main", "sha": "def456"},
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z"
                }]
                """
                return MockURLProtocol.successResponse(for: request, jsonString: prJson)
            }
        }

        let detectedChanges = SendableBox<[PRPoller.PRChange]>([])
        poller.startPolling { changes in
            detectedChanges.value = changes
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        // Should still detect PR from repo2 despite repo1 error
        XCTAssertEqual(detectedChanges.value.count, 1)
        if let change = detectedChanges.value.first {
            XCTAssertEqual(change.repo, "owner/repo2")
        }

        poller.stopPolling()
    }

    func testPollHandlesEmptyReposConfig() async throws {
        // When repos is empty, poller should try to discover repos
        // But since we're mocking, it won't find any
        let config = makeConfig(repos: [])
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())
        MockURLProtocol.requestHandler = { request in
            // Return empty repos for discovery
            if request.url?.path.contains("/user/repos") == true {
                return MockURLProtocol.successResponse(for: request, jsonString: "[]")
            }
            return MockURLProtocol.successResponse(for: request, jsonString: "[]")
        }

        let detectedChanges = SendableBox<[PRPoller.PRChange]>([])
        poller.startPolling { changes in
            detectedChanges.value = changes
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should handle gracefully with no changes
        XCTAssertTrue(detectedChanges.value.isEmpty)

        poller.stopPolling()
    }
}

// MARK: - PRPoller Edge Case Tests

final class PRPollerEdgeCaseTests: XCTestCase {

    private func makeConfig(repos: [String] = ["owner/repo"]) -> Config {
        Config(
            githubToken: "test-token",
            githubUsername: "testuser",
            repos: repos,
            tokens: [:],
            cloneRoot: "/tmp/test",
            pollIntervalSeconds: 60,
            ghosttyPath: "/Applications/Ghostty.app",
            nvimPath: "/opt/homebrew/bin/nvim",
            notifications: NotificationConfig()
        )
    }

    func testRapidStartStopCycles() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: "[]")
        }

        // Rapid start/stop
        for _ in 0 ..< 5 {
            poller.startPolling { _ in }
            poller.stopPolling()
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Should end up not polling
        XCTAssertFalse(poller.isPolling)
    }

    func testHandlesNetworkTimeout() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        MockURLProtocol.requestHandler = { _ in
            throw MockURLProtocol.networkError(code: NSURLErrorTimedOut)
        }

        poller.startPolling { _ in }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should not crash, callback may or may not be called with empty
        XCTAssertTrue(poller.isPolling)

        poller.stopPolling()
    }

    func testHandlesMalformedJSON() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: "{ not valid json }")
        }

        let detectedChanges = SendableBox<[PRPoller.PRChange]>([])
        poller.startPolling { changes in
            detectedChanges.value = changes
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should handle gracefully with no changes
        XCTAssertTrue(detectedChanges.value.isEmpty)
        XCTAssertTrue(poller.isPolling)

        poller.stopPolling()
    }

    func testHandlesPRWithLongTitle() async throws {
        let config = makeConfig()
        MockURLProtocol.reset()
        let poller = PRPoller(config: config, session: MockURLProtocol.mockSession())

        let longTitle = String(repeating: "A", count: 1000)
        let prJson = """
        [{
            "id": 1,
            "number": 42,
            "title": "\(longTitle)",
            "body": "Body",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/42",
            "user": {"id": 1, "login": "otheruser", "avatar_url": null},
            "head": {"ref": "feature", "sha": "abc123"},
            "base": {"ref": "main", "sha": "def456"},
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }]
        """

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: prJson)
        }

        let detectedChanges = SendableBox<[PRPoller.PRChange]>([])
        poller.startPolling { changes in
            detectedChanges.value = changes
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(detectedChanges.value.count, 1)
        XCTAssertEqual(detectedChanges.value.first?.pr.title, longTitle)

        poller.stopPolling()
    }
}
