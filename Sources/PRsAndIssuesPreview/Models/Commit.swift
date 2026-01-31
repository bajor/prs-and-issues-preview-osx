import Foundation

/// Represents a GitHub Commit
public struct Commit: Codable, Equatable, Sendable {
    public let sha: String
    public let commit: CommitDetails
    public let author: GitHubUser?

    public struct CommitDetails: Codable, Equatable, Sendable {
        public let message: String
        public let author: CommitAuthor?

        public struct CommitAuthor: Codable, Equatable, Sendable {
            public let name: String
            public let email: String
            public let date: Date
        }
    }

    /// Get the first line of the commit message (summary)
    public var summary: String {
        commit.message.components(separatedBy: "\n").first ?? commit.message
    }
}
