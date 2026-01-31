import Foundation

/// Represents a GitHub Issue
public struct Issue: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let htmlUrl: String
    public let user: GitHubUser
    public let createdAt: Date
    public let updatedAt: Date
    /// Issues endpoint also returns PRs - this field is present only for PRs
    public let pullRequest: IssuePullRequest?

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pullRequest = "pull_request"
    }
}

/// Minimal PR info included in issue responses (used to filter out PRs from issues list)
public struct IssuePullRequest: Codable, Equatable, Sendable {
    public let url: String
}
