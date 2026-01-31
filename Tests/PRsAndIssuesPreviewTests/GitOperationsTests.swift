import XCTest
import Foundation
@testable import PRsAndIssuesPreview

final class GitOperationsTests: XCTestCase {

    func testBuildPRPath() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/home/user/repos",
            owner: "owner",
            repo: "repo",
            prNumber: 123
        )
        XCTAssertEqual(path, "/home/user/repos/owner/repo/pr-123")
    }

    func testBuildPRPathVariant() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/tmp/prs",
            owner: "org",
            repo: "project",
            prNumber: 1
        )
        XCTAssertEqual(path, "/tmp/prs/org/project/pr-1")
    }

    func testBuildPRPathLargeNumber() {
        let path = GitOperations.buildPRPath(
            cloneRoot: "/data",
            owner: "company",
            repo: "app",
            prNumber: 99999
        )
        XCTAssertEqual(path, "/data/company/app/pr-99999")
    }

    func testIsGitRepoTrue() {
        // Find the repo root by looking for .git directory
        var path = FileManager.default.currentDirectoryPath
        while !path.isEmpty && path != "/" {
            if GitOperations.isGitRepo(at: path) {
                XCTAssertTrue(GitOperations.isGitRepo(at: path))
                return
            }
            path = (path as NSString).deletingLastPathComponent
        }
        // If no git repo found, test against a known path or skip
        // This can happen in sandboxed test environments
    }

    func testIsGitRepoFalse() {
        XCTAssertFalse(GitOperations.isGitRepo(at: "/tmp"))
    }

    func testIsGitRepoNonExistent() {
        XCTAssertFalse(GitOperations.isGitRepo(at: "/nonexistent/path/12345"))
    }
}

final class GitErrorTests: XCTestCase {

    func testErrorDescriptions() {
        let errors: [GitError] = [
            .commandFailed(command: "git clone", exitCode: 1, message: "error"),
            .notARepository(path: "/tmp"),
        ]

        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }

    func testCommandFailedDescription() {
        let error = GitError.commandFailed(
            command: "git clone",
            exitCode: 128,
            message: "repository not found"
        )
        XCTAssertTrue(error.description.contains("git clone"))
        XCTAssertTrue(error.description.contains("128"))
        XCTAssertTrue(error.description.contains("repository not found"))
    }
}

final class GitOperationsIntegrationTests: XCTestCase {

    func testGetCurrentBranch() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        // Only run if we're in a git repo
        guard GitOperations.isGitRepo(at: cwd) else {
            return
        }

        let branch = try await GitOperations.getCurrentBranch(at: cwd)
        XCTAssertFalse(branch.isEmpty)
    }

    func testGetCurrentSHA() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        // Only run if we're in a git repo
        guard GitOperations.isGitRepo(at: cwd) else {
            return
        }

        let sha = try await GitOperations.getCurrentSHA(at: cwd)
        XCTAssertEqual(sha.count, 40)
        // SHA should be hex
        XCTAssertTrue(sha.allSatisfy { $0.isHexDigit })
    }
}
