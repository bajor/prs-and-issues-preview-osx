import Foundation

/// Status of CI checks for a commit
public struct CheckStatus: Equatable, Sendable {
    /// Overall status
    public enum Status: String, Equatable, Sendable {
        case pending = "pending"
        case success = "success"
        case failure = "failure"
        case cancelled = "cancelled"
        case unknown = "unknown"
    }

    public let status: Status
    public let totalCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let pendingCount: Int

    /// Display string for menu
    public var displayString: String {
        switch status {
        case .pending:
            return "⏳ \(passedCount)/\(totalCount)"
        case .success:
            return "✅"
        case .failure:
            return "❌ \(failedCount) failed"
        case .cancelled:
            return "⚪️ cancelled"
        case .unknown:
            return ""
        }
    }

    /// Whether checks are still running
    public var isRunning: Bool {
        status == .pending
    }

    public init(status: Status, totalCount: Int = 0, passedCount: Int = 0, failedCount: Int = 0, pendingCount: Int = 0) {
        self.status = status
        self.totalCount = totalCount
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.pendingCount = pendingCount
    }
}

/// GitHub combined status response
struct CombinedStatusResponse: Codable {
    let state: String
    let totalCount: Int
    let statuses: [StatusItem]

    enum CodingKeys: String, CodingKey {
        case state
        case totalCount = "total_count"
        case statuses
    }

    struct StatusItem: Codable {
        let state: String
        let context: String
    }
}

/// GitHub check runs response
struct CheckRunsResponse: Codable {
    let totalCount: Int
    let checkRuns: [CheckRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }

    struct CheckRun: Codable {
        let id: Int
        let name: String
        let status: String  // queued, in_progress, completed
        let conclusion: String?  // success, failure, cancelled, skipped, etc.
    }
}
