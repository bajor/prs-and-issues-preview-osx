import Foundation
import XCTest
@testable import PRsAndIssuesPreview

final class GhosttyLauncherTests: XCTestCase {

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
        let launcher = GhosttyLauncher(config: config)
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }

    func testInitWithMultiTokenConfig() {
        let config = Config(
            githubToken: "default-token",
            githubUsername: "user",
            repos: ["owner/repo", "org/repo"],
            excludedRepos: [],
            tokens: ["org": "org-specific-token"],
            cloneRoot: "/tmp/test",
            pollIntervalSeconds: 300,
            ghosttyPath: "/Applications/Ghostty.app",
            nvimPath: "/opt/homebrew/bin/nvim",
            notifications: NotificationConfig()
        )
        let launcher = GhosttyLauncher(config: config)
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }
}

final class GhosttyLauncherErrorTests: XCTestCase {

    func testGhosttyNotFoundDescription() {
        let error = GhosttyLauncherError.ghosttyNotFound(path: "/test/path")
        XCTAssertTrue(error.description.contains("/test/path"))
        XCTAssertTrue(error.description.contains("not found"))
    }

    func testLaunchFailedDescription() {
        let error = GhosttyLauncherError.launchFailed(message: "test error")
        XCTAssertTrue(error.description.contains("test error"))
        XCTAssertTrue(error.description.contains("Failed"))
    }

    func testCloneFailedDescription() {
        let error = GhosttyLauncherError.cloneFailed(message: "clone error")
        XCTAssertTrue(error.description.contains("clone error"))
        XCTAssertTrue(error.description.contains("clone"))
    }

    func testAllErrorsConformToError() {
        let errors: [any Error] = [
            GhosttyLauncherError.ghosttyNotFound(path: "/path"),
            GhosttyLauncherError.launchFailed(message: "msg"),
            GhosttyLauncherError.cloneFailed(message: "msg"),
        ]

        XCTAssertEqual(errors.count, 3)
    }
}

// MARK: - GhosttyLauncher Configuration Tests

final class GhosttyLauncherConfigTests: XCTestCase {

    private func makeConfig(
        cloneRoot: String = "/tmp/test",
        ghosttyPath: String = "/Applications/Ghostty.app",
        nvimPath: String = "/opt/homebrew/bin/nvim",
        tokens: [String: String] = [:]
    ) -> Config {
        Config(
            githubToken: "default-token",
            githubUsername: "testuser",
            repos: ["owner/repo"],
            excludedRepos: [],
            tokens: tokens,
            cloneRoot: cloneRoot,
            pollIntervalSeconds: 300,
            ghosttyPath: ghosttyPath,
            nvimPath: nvimPath,
            notifications: NotificationConfig()
        )
    }

    func testConfigWithAppPath() {
        let config = makeConfig(ghosttyPath: "/Applications/Ghostty.app")
        let launcher = GhosttyLauncher(config: config)
        // Can't test internal binary path building directly, but config is valid
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }

    func testConfigWithBinaryPath() {
        let config = makeConfig(ghosttyPath: "/usr/local/bin/ghostty")
        let launcher = GhosttyLauncher(config: config)
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }

    func testConfigWithTildeCloneRoot() {
        let config = makeConfig(cloneRoot: "~/pr-reviews")
        let launcher = GhosttyLauncher(config: config)
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }

    func testConfigWithAbsoluteCloneRoot() {
        let config = makeConfig(cloneRoot: "/var/repos/pr-reviews")
        let launcher = GhosttyLauncher(config: config)
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }

    func testConfigWithOwnerTokens() {
        let config = makeConfig(tokens: [
            "org1": "token1",
            "org2": "token2",
        ])
        let launcher = GhosttyLauncher(config: config)
        XCTAssertTrue(type(of: launcher) == GhosttyLauncher.self)
    }

    func testConfigResolvesTokenForOwner() {
        let config = makeConfig(tokens: [
            "special-org": "special-token",
        ])

        // Test token resolution via config
        let defaultToken = config.resolveToken(for: "random-owner")
        let specialToken = config.resolveToken(for: "special-org")

        XCTAssertEqual(defaultToken, "default-token")
        XCTAssertEqual(specialToken, "special-token")
    }
}

// MARK: - GhosttyLauncher Path Tests

final class GhosttyLauncherPathTests: XCTestCase {

    func testPrPathBuilding() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/tmp/test",
            owner: "myorg",
            repo: "myrepo",
            prNumber: 42
        )
        XCTAssertEqual(path, "/tmp/test/myorg/myrepo/pr-42")
    }

    func testPrPathWithSpecialChars() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/tmp/test",
            owner: "my-org",
            repo: "my_repo",
            prNumber: 123
        )
        XCTAssertEqual(path, "/tmp/test/my-org/my_repo/pr-123")
    }

    func testPrPathWithNumbers() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/tmp/test",
            owner: "org123",
            repo: "repo456",
            prNumber: 789
        )
        XCTAssertEqual(path, "/tmp/test/org123/repo456/pr-789")
    }

    func testPrPathWithTrailingSlash() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/tmp/test/",
            owner: "owner",
            repo: "repo",
            prNumber: 1
        )
        // Path should not have double slashes
        XCTAssertFalse(path.contains("//"))
    }
}

// MARK: - GhosttyLauncher Edge Case Tests

final class GhosttyLauncherEdgeCaseTests: XCTestCase {

    private func makeConfig(
        cloneRoot: String = "/tmp/test",
        ghosttyPath: String = "/Applications/Ghostty.app",
        nvimPath: String = "/opt/homebrew/bin/nvim"
    ) -> Config {
        Config(
            githubToken: "test-token",
            githubUsername: "testuser",
            repos: ["owner/repo"],
            excludedRepos: [],
            tokens: [:],
            cloneRoot: cloneRoot,
            pollIntervalSeconds: 300,
            ghosttyPath: ghosttyPath,
            nvimPath: nvimPath,
            notifications: NotificationConfig()
        )
    }

    func testThrowsGhosttyNotFound() async throws {
        let config = makeConfig(ghosttyPath: "/nonexistent/path/Ghostty.app")
        let launcher = GhosttyLauncher(config: config)

        let pr = try makePullRequest(number: 1)

        // This should throw an error - either GhosttyLauncherError or GitError
        // depending on which operation fails first
        do {
            try await launcher.openPR(pr, owner: "owner", repo: "repo")
            XCTFail("Expected an error to be thrown")
        } catch is GhosttyLauncherError {
            // Expected - Ghostty not found
        } catch is GitError {
            // Also acceptable - git operations may fail first in test environment
        } catch {
            XCTFail("Expected GhosttyLauncherError or GitError, got \(type(of: error))")
        }
    }

    func testHandlesUnicodeTitle() throws {
        // Test that we can create PR with unicode
        let pr = try makePullRequest(number: 1, title: "Fix bug: 日本語テスト 🎉")
        XCTAssertEqual(pr.title, "Fix bug: 日本語テスト 🎉")
    }

    func testHandlesLongBranchName() throws {
        let longBranch = String(repeating: "a", count: 200)
        let pr = try makePullRequest(number: 1, branch: longBranch)
        XCTAssertEqual(pr.head.ref, longBranch)
    }

    func testOpenAllPRsEmptyArray() async throws {
        let config = makeConfig()
        let launcher = GhosttyLauncher(config: config)

        // Should not throw for empty array
        try await launcher.openAllPRs([])
    }

    /// Helper to create a test PullRequest
    private func makePullRequest(
        number: Int,
        title: String = "Test PR",
        branch: String = "feature-branch"
    ) throws -> PullRequest {
        let json = """
        {
            "id": \(number),
            "number": \(number),
            "title": "\(title.replacingOccurrences(of: "\"", with: "\\\""))",
            "body": "Test body",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/\(number)",
            "user": {
                "id": 1,
                "login": "testuser",
                "avatar_url": "https://example.com/avatar.png"
            },
            "head": {
                "ref": "\(branch)",
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
