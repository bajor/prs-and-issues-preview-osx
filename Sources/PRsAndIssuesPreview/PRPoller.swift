import Foundation

/// Polls GitHub for PR updates at configured intervals
public final class PRPoller: @unchecked Sendable {
    // MARK: - Types

    /// Represents a change detected in a PR
    public struct PRChange: Equatable, Sendable {
        public let pr: PullRequest
        public let repo: String
        public let changeType: ChangeType

        public enum ChangeType: Equatable, Sendable {
            case newPR
            case newCommits(oldSHA: String, newSHA: String)
            case newComments(count: Int)
            case statusChanged(from: String?, to: String?)
        }
    }

    /// Callback for when changes are detected
    public typealias ChangeHandler = @Sendable ([PRChange]) -> Void

    // MARK: - Properties

    /// Configuration (used for repo list and token resolution)
    private let config: Config

    /// URLSession for network requests (injectable for testing)
    private let session: URLSession?

    /// Polling timer
    private var timer: Timer?

    /// Last known PR states (repo -> [pr number -> state])
    private var lastKnownStates: [String: [Int: PRState]] = [:]

    /// Cached discovered repos with their tokens (when config.repos is empty)
    private var discoveredRepos: [(repo: String, token: String)]?

    /// Current repo -> token mapping for easy lookup
    private var repoTokenMap: [String: String] = [:]

    /// Change handler callback
    private var onChanges: ChangeHandler?

    /// Serial queue for thread-safe state access
    private let stateQueue = DispatchQueue(label: "com.pr-review.poller.state")

    /// Whether polling is active
    public private(set) var isPolling: Bool = false

    // MARK: - Initialization

    public init(config: Config, session: URLSession? = nil) {
        self.config = config
        self.session = session
    }

    // MARK: - Private Helpers

    /// Create a GitHub API client for the given owner
    /// Returns nil if no valid token exists for this owner
    private func api(for owner: String) -> GitHubAPI? {
        let token = config.resolveToken(for: owner)
        guard !token.isEmpty else { return nil }
        return GitHubAPI(token: token, session: session)
    }

    /// Discover all repos accessible by configured tokens
    /// Returns array of (repo, token) tuples so we can use the correct token when fetching PRs
    private func discoverRepos() async -> [(repo: String, token: String)] {
        var discoveredRepos: [(repo: String, token: String)] = []

        await withTaskGroup(of: [(repo: String, token: String)].self) { group in
            // Discover repos from each token in the tokens map
            for (_, token) in config.tokens {
                let capturedToken = token
                let capturedSession = session
                group.addTask {
                    let api = GitHubAPI(token: capturedToken, session: capturedSession)
                    do {
                        let repos = try await api.listRepos()
                        return repos.map { (repo: $0.fullName, token: capturedToken) }
                    } catch {
                        print("Error discovering repos: \(error)")
                        return []
                    }
                }
            }

            // Also check default token if not empty and not already in tokens
            if !config.githubToken.isEmpty {
                let tokenAlreadyUsed = config.tokens.values.contains(config.githubToken)
                if !tokenAlreadyUsed {
                    let defaultToken = config.githubToken
                    let capturedSession = session
                    group.addTask {
                        let api = GitHubAPI(token: defaultToken, session: capturedSession)
                        do {
                            let repos = try await api.listRepos()
                            return repos.map { (repo: $0.fullName, token: defaultToken) }
                        } catch {
                            print("Error discovering repos with default token: \(error)")
                            return []
                        }
                    }
                }
            }

            for await results in group {
                discoveredRepos.append(contentsOf: results)
            }
        }

        // Dedupe by repo name (keep first token found for each repo)
        var seen: Set<String> = []
        let deduped = discoveredRepos.filter { seen.insert($0.repo).inserted }

        return deduped.sorted { $0.repo < $1.repo }
    }

    /// Get repos to poll with their tokens
    /// For explicit config.repos, resolve tokens via config.resolveToken
    /// For auto-discovered repos, use the token that discovered them
    private func getReposToPoll() async -> [(repo: String, token: String)] {
        let reposWithTokens: [(repo: String, token: String)]

        if !config.repos.isEmpty {
            // Use explicit repos from config, resolve tokens
            reposWithTokens = config.repos.compactMap { repo -> (repo: String, token: String)? in
                let parts = repo.split(separator: "/")
                guard parts.count == 2 else { return nil }
                let owner = String(parts[0])
                let token = config.resolveToken(for: owner)
                guard !token.isEmpty else { return nil }
                return (repo: repo, token: token)
            }
        } else if let cached = stateQueue.sync(execute: { discoveredRepos }) {
            reposWithTokens = cached
        } else {
            // Discover repos
            let discovered = await discoverRepos()
            stateQueue.sync {
                discoveredRepos = discovered
            }
            reposWithTokens = discovered
        }

        // Filter out excluded repos
        let filteredRepos = reposWithTokens.filter { !config.isExcluded($0.repo) }

        // Build repo -> token mapping for later use
        stateQueue.sync {
            repoTokenMap = Dictionary(uniqueKeysWithValues: filteredRepos.map { ($0.repo, $0.token) })
        }

        return filteredRepos
    }

    // MARK: - Public API

    /// Start polling for PR updates
    /// - Parameter onChanges: Callback invoked when changes are detected
    public func startPolling(onChanges: @escaping ChangeHandler) {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !isPolling else { return false }
            self.onChanges = onChanges
            isPolling = true
            return true
        }

        guard shouldStart else { return }

        // Schedule timer on main run loop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let interval = TimeInterval(self.config.pollIntervalSeconds)
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task {
                    await self?.poll()
                }
            }

            // Initial poll immediately
            Task {
                await self.poll()
            }
        }
    }

    /// Stop polling
    public func stopPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }

        stateQueue.sync {
            isPolling = false
            onChanges = nil
        }
    }

    /// Force an immediate poll
    public func pollNow() async {
        await poll()
    }

    /// Clear cached state (useful for testing)
    public func clearState() {
        stateQueue.sync {
            lastKnownStates.removeAll()
            discoveredRepos = nil
        }
    }

    // MARK: - Private Methods

    /// Perform a poll cycle
    private func poll() async {
        var allChanges: [PRChange] = []

        let reposWithTokens = await getReposToPoll()

        for (repo, token) in reposWithTokens {
            let parts = repo.split(separator: "/")
            guard parts.count == 2 else { continue }
            let owner = String(parts[0])
            let repoName = String(parts[1])

            // Use the token associated with this repo
            let repoAPI = GitHubAPI(token: token, session: session)

            do {
                let prs = try await repoAPI.listPRs(owner: owner, repo: repoName)
                let changes = detectChanges(for: repo, prs: prs)
                allChanges.append(contentsOf: changes)

                // Update stored state
                updateState(for: repo, prs: prs)
            } catch {
                // Log error but continue with other repos
                print("Error polling \(repo): \(error)")
            }
        }

        // Filter out changes by the current user
        let filteredChanges = allChanges.filter { change in
            change.pr.user.login != config.githubUsername
        }

        // Notify if there are changes
        if !filteredChanges.isEmpty {
            let handler = stateQueue.sync { onChanges }
            handler?(filteredChanges)
        }
    }

    /// Detect changes between current and previous state
    private func detectChanges(for repo: String, prs: [PullRequest]) -> [PRChange] {
        var changes: [PRChange] = []

        let previousStates = stateQueue.sync { lastKnownStates[repo] ?? [:] }

        for pr in prs {
            if let previousState = previousStates[pr.number] {
                // Check for commit changes
                if pr.head.sha != previousState.headSHA {
                    changes.append(PRChange(
                        pr: pr,
                        repo: repo,
                        changeType: .newCommits(oldSHA: previousState.headSHA, newSHA: pr.head.sha)
                    ))
                }

                // Check for comment count changes
                // Note: This is a simple heuristic - for accurate tracking we'd need to fetch comments
                // and compare. For now, we rely on PR metadata updates.
            } else {
                // New PR
                changes.append(PRChange(
                    pr: pr,
                    repo: repo,
                    changeType: .newPR
                ))
            }
        }

        return changes
    }

    /// Update stored state with current PR data
    private func updateState(for repo: String, prs: [PullRequest]) {
        var newStates: [Int: PRState] = [:]
        for pr in prs {
            newStates[pr.number] = PRState(
                headSHA: pr.head.sha,
                updatedAt: pr.updatedAt
            )
        }

        stateQueue.sync {
            lastKnownStates[repo] = newStates
        }
    }
}

// MARK: - Supporting Types

/// Cached state for a PR
private struct PRState {
    let headSHA: String
    let updatedAt: Date
}
