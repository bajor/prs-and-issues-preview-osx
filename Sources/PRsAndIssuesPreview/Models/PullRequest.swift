import Foundation

/// Represents a GitHub Pull Request
public struct PullRequest: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let htmlUrl: String
    public let user: GitHubUser
    public let head: GitRef
    public let base: GitRef
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, head, base
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Represents a GitHub user
public struct GitHubUser: Codable, Equatable, Sendable {
    public let id: Int
    public let login: String
    public let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, login
        case avatarUrl = "avatar_url"
    }
}

/// Represents a git reference (branch)
public struct GitRef: Codable, Equatable, Sendable {
    public let ref: String
    public let sha: String
    public let repo: Repository?
}

/// Repository info within a git ref
public struct Repository: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let htmlUrl: String
    public let cloneUrl: String
    public let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, archived
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
    }
}
