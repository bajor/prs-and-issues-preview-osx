import XCTest
import Foundation
@testable import PRsAndIssuesPreview

final class GitHubAPITests: XCTestCase {

    func testBaseURL() {
        XCTAssertEqual(GitHubAPI.baseURL, "https://api.github.com")
    }

    func testParseValidPRUrl() {
        let result = GitHubAPI.parsePRUrl("https://github.com/owner/repo/pull/123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "repo")
        XCTAssertEqual(result?.number, 123)
    }

    func testParsePRUrlWithSpecialChars() {
        let result = GitHubAPI.parsePRUrl("https://github.com/my-org/my_repo/pull/456")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.owner, "my-org")
        XCTAssertEqual(result?.repo, "my_repo")
        XCTAssertEqual(result?.number, 456)
    }

    func testParsePRUrlWithNumbers() {
        let result = GitHubAPI.parsePRUrl("https://github.com/org123/repo456/pull/789")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.owner, "org123")
        XCTAssertEqual(result?.repo, "repo456")
        XCTAssertEqual(result?.number, 789)
    }

    func testParsePRUrlWithTrailingPath() {
        let result = GitHubAPI.parsePRUrl("https://github.com/owner/repo/pull/123/files")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "repo")
        XCTAssertEqual(result?.number, 123)
    }

    func testParseInvalidUrl() {
        let result = GitHubAPI.parsePRUrl("https://example.com/not/a/pr")
        XCTAssertNil(result)
    }

    func testParseNonPRUrl() {
        let result = GitHubAPI.parsePRUrl("https://github.com/owner/repo/issues/123")
        XCTAssertNil(result)
    }

    func testParseEmptyString() {
        let result = GitHubAPI.parsePRUrl("")
        XCTAssertNil(result)
    }
}

final class GitHubAPIErrorTests: XCTestCase {

    func testErrorDescriptions() {
        let errors: [GitHubAPIError] = [
            .invalidURL("bad-url"),
            .invalidResponse,
            .httpError(statusCode: 404),
            .apiError(statusCode: 401, message: "Bad credentials"),
            .decodingError("Test error"),
        ]

        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }

    func testApiErrorDescription() {
        let error = GitHubAPIError.apiError(statusCode: 401, message: "Bad credentials")
        XCTAssertTrue(error.description.contains("401"))
        XCTAssertTrue(error.description.contains("Bad credentials"))
    }
}

final class ModelDecodingTests: XCTestCase {

    func testDecodePullRequest() throws {
        let json = """
        {
            "id": 1,
            "number": 42,
            "title": "Test PR",
            "body": "Description",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/42",
            "user": {
                "id": 100,
                "login": "testuser",
                "avatar_url": "https://avatars.githubusercontent.com/u/100"
            },
            "head": {
                "ref": "feature-branch",
                "sha": "abc123",
                "repo": null
            },
            "base": {
                "ref": "main",
                "sha": "def456",
                "repo": null
            },
            "created_at": "2026-01-03T10:00:00Z",
            "updated_at": "2026-01-03T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pr = try decoder.decode(PullRequest.self, from: Data(json.utf8))

        XCTAssertEqual(pr.id, 1)
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Test PR")
        XCTAssertEqual(pr.state, "open")
        XCTAssertEqual(pr.user.login, "testuser")
        XCTAssertEqual(pr.head.ref, "feature-branch")
        XCTAssertEqual(pr.base.ref, "main")
    }

    func testDecodePRFile() throws {
        let json = """
        {
            "sha": "abc123",
            "filename": "src/main.rs",
            "status": "modified",
            "additions": 10,
            "deletions": 5,
            "changes": 15,
            "patch": "@@ -1,5 +1,10 @@"
        }
        """

        let file = try JSONDecoder().decode(PRFile.self, from: Data(json.utf8))

        XCTAssertEqual(file.sha, "abc123")
        XCTAssertEqual(file.filename, "src/main.rs")
        XCTAssertEqual(file.status, "modified")
        XCTAssertEqual(file.additions, 10)
        XCTAssertEqual(file.deletions, 5)
        XCTAssertNotNil(file.patch)
    }

    func testDecodePRComment() throws {
        let json = """
        {
            "id": 999,
            "body": "This looks good!",
            "user": {
                "id": 100,
                "login": "reviewer",
                "avatar_url": null
            },
            "path": "src/lib.rs",
            "line": 42,
            "side": "RIGHT",
            "commit_id": "abc123",
            "created_at": "2026-01-03T10:00:00Z",
            "updated_at": "2026-01-03T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let comment = try decoder.decode(PRComment.self, from: Data(json.utf8))

        XCTAssertEqual(comment.id, 999)
        XCTAssertEqual(comment.body, "This looks good!")
        XCTAssertEqual(comment.path, "src/lib.rs")
        XCTAssertEqual(comment.line, 42)
        XCTAssertEqual(comment.side, "RIGHT")
    }

    func testReviewEventEncoding() throws {
        XCTAssertEqual(ReviewEvent.approve.rawValue, "APPROVE")
        XCTAssertEqual(ReviewEvent.requestChanges.rawValue, "REQUEST_CHANGES")
        XCTAssertEqual(ReviewEvent.comment.rawValue, "COMMENT")
    }
}

// MARK: - API Behavior Tests

final class GitHubAPIBehaviorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    // MARK: - listPRs Tests

    func testListPRsSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/repos/owner/repo/pulls")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return MockURLProtocol.successResponse(
                for: request,
                jsonString: MockResponses.pullRequestList
            )
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let prs = try await api.listPRs(owner: "owner", repo: "repo")

        XCTAssertEqual(prs.count, 2)
        XCTAssertEqual(prs[0].number, 42)
        XCTAssertEqual(prs[0].title, "Add new feature")
        XCTAssertEqual(prs[1].number, 43)
    }

    func testListPRsEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: MockResponses.emptyList)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let prs = try await api.listPRs(owner: "owner", repo: "repo")

        XCTAssertTrue(prs.isEmpty)
    }

    func testListPRsPagination() async throws {
        let requestCount = SendableBox(0)
        MockURLProtocol.requestHandler = { request in
            requestCount.value += 1
            if requestCount.value == 1 {
                // First page with Link header
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: "[{\"id\":1,\"number\":1,\"title\":\"PR 1\",\"body\":\"\",\"state\":\"open\",\"html_url\":\"url\",\"user\":{\"id\":1,\"login\":\"u\",\"avatar_url\":null},\"head\":{\"ref\":\"b\",\"sha\":\"s\",\"repo\":null},\"base\":{\"ref\":\"m\",\"sha\":\"s\",\"repo\":null},\"created_at\":\"2026-01-01T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\"}]",
                    linkHeader: "<https://api.github.com/repos/owner/repo/pulls?page=2>; rel=\"next\""
                )
            } else {
                // Second page, no Link header
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: "[{\"id\":2,\"number\":2,\"title\":\"PR 2\",\"body\":\"\",\"state\":\"open\",\"html_url\":\"url\",\"user\":{\"id\":1,\"login\":\"u\",\"avatar_url\":null},\"head\":{\"ref\":\"b\",\"sha\":\"s\",\"repo\":null},\"base\":{\"ref\":\"m\",\"sha\":\"s\",\"repo\":null},\"created_at\":\"2026-01-01T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\"}]"
                )
            }
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let prs = try await api.listPRs(owner: "owner", repo: "repo")

        XCTAssertEqual(requestCount.value, 2)
        XCTAssertEqual(prs.count, 2)
        XCTAssertEqual(prs[0].number, 1)
        XCTAssertEqual(prs[1].number, 2)
    }

    // MARK: - getPR Tests

    func testGetPRSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/repos/owner/repo/pulls/42")
            return MockURLProtocol.successResponse(
                for: request,
                jsonString: MockResponses.pullRequest
            )
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let pr = try await api.getPR(owner: "owner", repo: "repo", number: 42)

        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Add new feature")
        XCTAssertEqual(pr.head.ref, "feature-branch")
    }

    func testGetPRNotFound() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.errorResponse(for: request, statusCode: 404, message: "Not Found")
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)

        do {
            _ = try await api.getPR(owner: "owner", repo: "repo", number: 999)
            XCTFail("Expected GitHubAPIError to be thrown")
        } catch is GitHubAPIError {
            // Expected
        }
    }

    func testGetPRUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.errorResponse(for: request, statusCode: 401, message: "Bad credentials")
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "bad-token", session: session)

        do {
            _ = try await api.getPR(owner: "owner", repo: "repo", number: 42)
            XCTFail("Expected GitHubAPIError to be thrown")
        } catch is GitHubAPIError {
            // Expected
        }
    }

    // MARK: - getPRFiles Tests

    func testGetPRFilesSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/repos/owner/repo/pulls/42/files")
            return MockURLProtocol.successResponse(
                for: request,
                jsonString: MockResponses.prFiles
            )
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let files = try await api.getPRFiles(owner: "owner", repo: "repo", number: 42)

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].filename, "src/main.swift")
        XCTAssertEqual(files[0].status, "modified")
        XCTAssertEqual(files[1].filename, "src/utils.swift")
        XCTAssertEqual(files[1].status, "added")
    }

    func testGetPRFilesEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: MockResponses.prFilesEmpty)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let files = try await api.getPRFiles(owner: "owner", repo: "repo", number: 42)

        XCTAssertTrue(files.isEmpty)
    }

    // MARK: - getPRComments Tests

    func testGetPRCommentsSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/repos/owner/repo/pulls/42/comments")
            return MockURLProtocol.successResponse(
                for: request,
                jsonString: MockResponses.prComments
            )
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let comments = try await api.getPRComments(owner: "owner", repo: "repo", number: 42)

        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].body, "This looks good!")
        XCTAssertEqual(comments[0].path, "src/main.swift")
        XCTAssertEqual(comments[1].path, "src/utils.swift")
    }

    func testGetPRCommentsEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: MockResponses.prCommentsEmpty)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let comments = try await api.getPRComments(owner: "owner", repo: "repo", number: 42)

        XCTAssertTrue(comments.isEmpty)
    }

    // MARK: - getCheckStatus Tests

    func testGetCheckStatusSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("check-runs") == true {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.checkRunsSuccess
                )
            } else {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.combinedStatusEmpty
                )
            }
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let status = try await api.getCheckStatus(owner: "owner", repo: "repo", ref: "abc123")

        XCTAssertEqual(status.status, .success)
        XCTAssertEqual(status.totalCount, 2)
        XCTAssertEqual(status.passedCount, 2)
        XCTAssertEqual(status.failedCount, 0)
        XCTAssertEqual(status.pendingCount, 0)
    }

    func testGetCheckStatusFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("check-runs") == true {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.checkRunsFailed
                )
            } else {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.combinedStatusEmpty
                )
            }
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let status = try await api.getCheckStatus(owner: "owner", repo: "repo", ref: "abc123")

        XCTAssertEqual(status.status, .failure)
        XCTAssertEqual(status.failedCount, 1)
        XCTAssertEqual(status.passedCount, 1)
    }

    func testGetCheckStatusPending() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("check-runs") == true {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.checkRunsPending
                )
            } else {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.combinedStatusEmpty
                )
            }
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let status = try await api.getCheckStatus(owner: "owner", repo: "repo", ref: "abc123")

        XCTAssertEqual(status.status, .pending)
        XCTAssertEqual(status.pendingCount, 1)
    }

    func testGetCheckStatusUnknown() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("check-runs") == true {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.checkRunsEmpty
                )
            } else {
                return MockURLProtocol.successResponse(
                    for: request,
                    jsonString: MockResponses.combinedStatusEmpty
                )
            }
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let status = try await api.getCheckStatus(owner: "owner", repo: "repo", ref: "abc123")

        XCTAssertEqual(status.status, .unknown)
        XCTAssertEqual(status.totalCount, 0)
    }

    // MARK: - getLastCommit Tests

    func testGetLastCommitSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: MockResponses.commits)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let commit = try await api.getLastCommit(owner: "owner", repo: "repo", number: 42)

        XCTAssertNotNil(commit)
        XCTAssertEqual(commit?.sha, "def456")
        XCTAssertEqual(commit?.commit.message, "Add feature")
    }

    func testGetLastCommitEmpty() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: MockResponses.commitsEmpty)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)
        let commit = try await api.getLastCommit(owner: "owner", repo: "repo", number: 42)

        XCTAssertNil(commit)
    }
}

// MARK: - API Error Handling Tests

final class GitHubAPIErrorHandlingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testRateLimitError() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.errorResponse(for: request, statusCode: 403, message: "API rate limit exceeded")
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)

        do {
            _ = try await api.listPRs(owner: "owner", repo: "repo")
            XCTFail("Expected error to be thrown")
        } catch let error as GitHubAPIError {
            XCTAssertTrue(error.description.contains("403"))
            XCTAssertTrue(error.description.contains("rate limit"))
        }
    }

    func testServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.errorResponse(for: request, statusCode: 500, message: "Internal Server Error")
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)

        do {
            _ = try await api.getPR(owner: "owner", repo: "repo", number: 42)
            XCTFail("Expected GitHubAPIError to be thrown")
        } catch is GitHubAPIError {
            // Expected
        }
    }

    func testNetworkTimeout() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw MockURLProtocol.networkError(code: NSURLErrorTimedOut)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)

        do {
            _ = try await api.listPRs(owner: "owner", repo: "repo")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    func testNetworkConnectionFailure() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw MockURLProtocol.networkError(code: NSURLErrorNotConnectedToInternet)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)

        do {
            _ = try await api.getPR(owner: "owner", repo: "repo", number: 42)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    func testMalformedJSON() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.successResponse(for: request, jsonString: "{ invalid json }")
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "test-token", session: session)

        do {
            _ = try await api.getPR(owner: "owner", repo: "repo", number: 42)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    func testAuthorizationHeader() async throws {
        let capturedRequest = SendableBox<URLRequest?>(nil)
        MockURLProtocol.requestHandler = { request in
            capturedRequest.value = request
            return MockURLProtocol.successResponse(for: request, jsonString: MockResponses.emptyList)
        }

        let session = MockURLProtocol.mockSession()
        let api = GitHubAPI(token: "my-secret-token", session: session)
        _ = try await api.listPRs(owner: "owner", repo: "repo")

        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-token")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }
}
