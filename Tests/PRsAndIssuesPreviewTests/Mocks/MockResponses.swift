import Foundation

/// Pre-defined mock responses for GitHub API testing
enum MockResponses {

    // MARK: - Pull Requests

    static let pullRequest = """
    {
        "id": 1,
        "number": 42,
        "title": "Add new feature",
        "body": "This PR adds an amazing new feature.",
        "state": "open",
        "html_url": "https://github.com/owner/repo/pull/42",
        "user": {
            "id": 100,
            "login": "testuser",
            "avatar_url": "https://avatars.githubusercontent.com/u/100"
        },
        "head": {
            "ref": "feature-branch",
            "sha": "abc123def456",
            "repo": null
        },
        "base": {
            "ref": "main",
            "sha": "def456abc123",
            "repo": null
        },
        "created_at": "2026-01-03T10:00:00Z",
        "updated_at": "2026-01-03T12:00:00Z"
    }
    """

    static let pullRequestList = """
    [
        {
            "id": 1,
            "number": 42,
            "title": "Add new feature",
            "body": "Description",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/42",
            "user": {"id": 100, "login": "testuser", "avatar_url": null},
            "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
            "base": {"ref": "main", "sha": "def456", "repo": null},
            "created_at": "2026-01-03T10:00:00Z",
            "updated_at": "2026-01-03T12:00:00Z"
        },
        {
            "id": 2,
            "number": 43,
            "title": "Fix bug",
            "body": "Bug fix",
            "state": "open",
            "html_url": "https://github.com/owner/repo/pull/43",
            "user": {"id": 101, "login": "otheruser", "avatar_url": null},
            "head": {"ref": "bugfix-branch", "sha": "xyz789", "repo": null},
            "base": {"ref": "main", "sha": "def456", "repo": null},
            "created_at": "2026-01-04T10:00:00Z",
            "updated_at": "2026-01-04T12:00:00Z"
        }
    ]
    """

    static let emptyList = "[]"

    // MARK: - PR Files

    static let prFiles = """
    [
        {
            "sha": "abc123",
            "filename": "src/main.swift",
            "status": "modified",
            "additions": 10,
            "deletions": 5,
            "changes": 15,
            "patch": "@@ -1,5 +1,10 @@\\n-old line\\n+new line"
        },
        {
            "sha": "def456",
            "filename": "src/utils.swift",
            "status": "added",
            "additions": 50,
            "deletions": 0,
            "changes": 50,
            "patch": "@@ -0,0 +1,50 @@\\n+// New file"
        }
    ]
    """

    static let prFilesEmpty = "[]"

    // MARK: - Comments

    static let prComments = """
    [
        {
            "id": 999,
            "body": "This looks good!",
            "user": {"id": 100, "login": "reviewer", "avatar_url": null},
            "path": "src/main.swift",
            "line": 42,
            "side": "RIGHT",
            "commit_id": "abc123",
            "created_at": "2026-01-03T10:00:00Z",
            "updated_at": "2026-01-03T10:00:00Z"
        },
        {
            "id": 1000,
            "body": "Consider refactoring this.",
            "user": {"id": 101, "login": "maintainer", "avatar_url": null},
            "path": "src/utils.swift",
            "line": 10,
            "side": "RIGHT",
            "commit_id": "abc123",
            "created_at": "2026-01-03T11:00:00Z",
            "updated_at": "2026-01-03T11:00:00Z"
        }
    ]
    """

    static let prCommentsEmpty = "[]"

    static let newComment = """
    {
        "id": 1001,
        "body": "New comment",
        "user": {"id": 100, "login": "testuser", "avatar_url": null},
        "path": "src/main.swift",
        "line": 50,
        "side": "RIGHT",
        "commit_id": "abc123",
        "created_at": "2026-01-03T12:00:00Z",
        "updated_at": "2026-01-03T12:00:00Z"
    }
    """

    // MARK: - Reviews

    static let reviewSubmitted = """
    {
        "id": 500,
        "user": {"id": 100, "login": "testuser", "avatar_url": null},
        "body": "LGTM!",
        "state": "APPROVED",
        "commit_id": "abc123",
        "submitted_at": "2026-01-03T12:00:00Z"
    }
    """

    // MARK: - Check Status

    static let checkRunsSuccess = """
    {
        "total_count": 2,
        "check_runs": [
            {
                "id": 1,
                "name": "CI",
                "status": "completed",
                "conclusion": "success",
                "started_at": "2026-01-03T10:00:00Z",
                "completed_at": "2026-01-03T10:05:00Z"
            },
            {
                "id": 2,
                "name": "Lint",
                "status": "completed",
                "conclusion": "success",
                "started_at": "2026-01-03T10:00:00Z",
                "completed_at": "2026-01-03T10:02:00Z"
            }
        ]
    }
    """

    static let checkRunsFailed = """
    {
        "total_count": 2,
        "check_runs": [
            {
                "id": 1,
                "name": "CI",
                "status": "completed",
                "conclusion": "failure",
                "started_at": "2026-01-03T10:00:00Z",
                "completed_at": "2026-01-03T10:05:00Z"
            },
            {
                "id": 2,
                "name": "Lint",
                "status": "completed",
                "conclusion": "success",
                "started_at": "2026-01-03T10:00:00Z",
                "completed_at": "2026-01-03T10:02:00Z"
            }
        ]
    }
    """

    static let checkRunsPending = """
    {
        "total_count": 2,
        "check_runs": [
            {
                "id": 1,
                "name": "CI",
                "status": "in_progress",
                "conclusion": null,
                "started_at": "2026-01-03T10:00:00Z",
                "completed_at": null
            },
            {
                "id": 2,
                "name": "Lint",
                "status": "completed",
                "conclusion": "success",
                "started_at": "2026-01-03T10:00:00Z",
                "completed_at": "2026-01-03T10:02:00Z"
            }
        ]
    }
    """

    static let checkRunsEmpty = """
    {
        "total_count": 0,
        "check_runs": []
    }
    """

    static let combinedStatusSuccess = """
    {
        "state": "success",
        "statuses": []
    }
    """

    static let combinedStatusEmpty = """
    {
        "state": "pending",
        "statuses": [],
        "total_count": 0
    }
    """

    // MARK: - Commits

    static let commits = """
    [
        {
            "sha": "abc123",
            "commit": {
                "message": "Initial commit",
                "author": {"name": "Test User", "email": "test@example.com", "date": "2026-01-03T10:00:00Z"}
            },
            "author": {"id": 100, "login": "testuser", "avatar_url": null}
        },
        {
            "sha": "def456",
            "commit": {
                "message": "Add feature",
                "author": {"name": "Test User", "email": "test@example.com", "date": "2026-01-03T11:00:00Z"}
            },
            "author": {"id": 100, "login": "testuser", "avatar_url": null}
        }
    ]
    """

    static let commitsEmpty = "[]"

    // MARK: - Repositories

    static let repositories = """
    [
        {
            "id": 1,
            "name": "repo1",
            "full_name": "owner/repo1",
            "private": false,
            "html_url": "https://github.com/owner/repo1",
            "description": "First repo",
            "default_branch": "main"
        },
        {
            "id": 2,
            "name": "repo2",
            "full_name": "owner/repo2",
            "private": true,
            "html_url": "https://github.com/owner/repo2",
            "description": "Second repo",
            "default_branch": "main"
        }
    ]
    """

    // MARK: - Errors

    static func error(message: String) -> String {
        """
        {"message": "\(message)", "documentation_url": "https://docs.github.com"}
        """
    }

    static let unauthorized = error(message: "Bad credentials")
    static let notFound = error(message: "Not Found")
    static let rateLimited = error(message: "API rate limit exceeded")
    static let validationFailed = error(message: "Validation Failed")
    static let serverError = error(message: "Internal Server Error")
}
