import XCTest
import Foundation
@testable import PRsAndIssuesPreview

final class ConfigTests: XCTestCase {

    func testDefaultsHaveAllFields() {
        let defaults = Config.defaults
        XCTAssertTrue(defaults.githubToken.isEmpty)
        XCTAssertTrue(defaults.githubUsername.isEmpty)
        XCTAssertTrue(defaults.repos.isEmpty)
        XCTAssertFalse(defaults.cloneRoot.isEmpty)
        XCTAssertEqual(defaults.pollIntervalSeconds, 300)
        XCTAssertFalse(defaults.ghosttyPath.isEmpty)
        XCTAssertFalse(defaults.nvimPath.isEmpty)
    }

    func testNotificationDefaults() {
        let defaults = NotificationConfig.defaults
        XCTAssertTrue(defaults.newCommits)
        XCTAssertTrue(defaults.newComments)
        XCTAssertTrue(defaults.sound)
    }
}

final class ConfigLoaderTests: XCTestCase {

    func testFileNotFound() {
        let path = "/nonexistent/path/config.json"
        XCTAssertThrowsError(try ConfigLoader.load(from: path)) { error in
            guard case ConfigError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error")
                return
            }
        }
    }

    func testInvalidJSON() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try "{ invalid json }".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        XCTAssertThrowsError(try ConfigLoader.load(from: tmpFile.path)) { error in
            guard case ConfigError.invalidJSON = error else {
                XCTFail("Expected invalidJSON error")
                return
            }
        }
    }

    func testMissingGithubToken() throws {
        let json = """
        {
            "github_username": "user",
            "repos": ["owner/repo"]
        }
        """
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        XCTAssertThrowsError(try ConfigLoader.load(from: tmpFile.path)) { error in
            guard case ConfigError.missingRequiredField(name: "github_token") = error else {
                XCTFail("Expected missingRequiredField error for github_token")
                return
            }
        }
    }

    func testMissingGithubUsername() throws {
        let json = """
        {
            "github_token": "ghp_xxx",
            "repos": ["owner/repo"]
        }
        """
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        XCTAssertThrowsError(try ConfigLoader.load(from: tmpFile.path)) { error in
            guard case ConfigError.missingRequiredField(name: "github_username") = error else {
                XCTFail("Expected missingRequiredField error for github_username")
                return
            }
        }
    }

    func testEmptyReposAllowed() throws {
        let json = """
        {
            "github_token": "ghp_xxx",
            "github_username": "user",
            "repos": []
        }
        """
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        // Empty repos is now valid - allows auto-discovery
        let config = try ConfigLoader.load(from: tmpFile.path)
        XCTAssertTrue(config.repos.isEmpty)
    }

    func testInvalidRepoFormat() throws {
        let json = """
        {
            "github_token": "ghp_xxx",
            "github_username": "user",
            "repos": ["invalid"]
        }
        """
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        XCTAssertThrowsError(try ConfigLoader.load(from: tmpFile.path)) { error in
            guard case ConfigError.invalidRepoFormat(repo: "invalid") = error else {
                XCTFail("Expected invalidRepoFormat error")
                return
            }
        }
    }

    func testLoadValidConfig() throws {
        let json = """
        {
            "github_token": "ghp_test123",
            "github_username": "testuser",
            "repos": ["owner/repo1", "owner/repo2"],
            "clone_root": "/tmp/test/repos"
        }
        """
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = try ConfigLoader.load(from: tmpFile.path)
        XCTAssertEqual(config.githubToken, "ghp_test123")
        XCTAssertEqual(config.githubUsername, "testuser")
        XCTAssertEqual(config.repos.count, 2)
        XCTAssertEqual(config.cloneRoot, "/tmp/test/repos")
    }

    func testMergeWithDefaults() throws {
        let json = """
        {
            "github_token": "ghp_test123",
            "github_username": "testuser",
            "repos": ["owner/repo"]
        }
        """
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = try ConfigLoader.load(from: tmpFile.path)
        // Should have default values
        XCTAssertEqual(config.pollIntervalSeconds, 300)
        XCTAssertEqual(config.ghosttyPath, "/Applications/Ghostty.app")
        XCTAssertTrue(config.notifications.newCommits)
    }

    func testExpandsTildePaths() {
        let expanded = ConfigLoader.expandPath("~/test/path")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasPrefix("/"))
    }

    func testValidatesRepoFormat() {
        XCTAssertTrue(ConfigLoader.isValidRepoFormat("owner/repo"))
        XCTAssertTrue(ConfigLoader.isValidRepoFormat("my-org/my-repo"))
        XCTAssertTrue(ConfigLoader.isValidRepoFormat("org_name/repo.name"))
        XCTAssertFalse(ConfigLoader.isValidRepoFormat("invalid"))
        XCTAssertFalse(ConfigLoader.isValidRepoFormat("a/b/c"))
        XCTAssertFalse(ConfigLoader.isValidRepoFormat(""))
    }
}

final class ConfigErrorTests: XCTestCase {

    func testErrorDescriptions() {
        let errors: [ConfigError] = [
            .fileNotFound(path: "/test/path"),
            .invalidJSON(message: "test error"),
            .missingRequiredField(name: "test_field"),
            .invalidRepoFormat(repo: "invalid"),
        ]

        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }
}
