import Foundation

/// Represents a file changed in a Pull Request
struct PRFile: Codable, Equatable {
    let sha: String
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let patch: String?
    let contentsUrl: String?

    enum CodingKeys: String, CodingKey {
        case sha, filename, status, additions, deletions, changes, patch
        case contentsUrl = "contents_url"
    }
}
