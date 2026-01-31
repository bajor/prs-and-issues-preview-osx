import Foundation

/// Represents a review comment on a Pull Request
struct PRComment: Codable, Identifiable, Equatable {
    let id: Int
    let body: String
    let user: GitHubUser
    let path: String?
    let line: Int?
    let side: String?
    let commitId: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, user, path, line, side
        case commitId = "commit_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Request body for creating a comment
struct CreateCommentRequest: Codable {
    let body: String
    let commitId: String
    let path: String
    let line: Int
    let side: String

    enum CodingKeys: String, CodingKey {
        case body, path, line, side
        case commitId = "commit_id"
    }
}

/// Request body for submitting a review
struct SubmitReviewRequest: Codable {
    let event: ReviewEvent
    let body: String?
}

/// Review event types
enum ReviewEvent: String, Codable {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

/// Response from submitting a review
struct ReviewResponse: Codable {
    let id: Int
    let state: String
    let body: String?
    let user: GitHubUser
}
