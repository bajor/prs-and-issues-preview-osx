import AppKit
import Foundation

/// Launches Ghostty terminal with Neovim for PR review
public final class GhosttyLauncher {
    // MARK: - Properties

    /// Configuration (used for paths and token resolution)
    private let config: Config

    // MARK: - Initialization

    public init(config: Config) {
        self.config = config
    }

    // MARK: - Public API

    /// Open a pull request in Ghostty + Neovim
    /// - Parameters:
    ///   - pr: The pull request to open
    ///   - owner: Repository owner
    ///   - repo: Repository name
    public func openPR(_ pr: PullRequest, owner: String, repo: String) async throws {
        // Expand clone root (handle ~)
        let cloneRoot = config.cloneRoot
        let expandedCloneRoot: String
        if cloneRoot.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expandedCloneRoot = home + cloneRoot.dropFirst()
        } else {
            expandedCloneRoot = cloneRoot
        }

        // Build the clone path
        let clonePath = GitOperations.buildPRPath(cloneRoot: expandedCloneRoot, owner: owner, repo: repo, prNumber: pr.number)

        // Ensure the clone directory exists
        let fileManager = FileManager.default
        let cloneURL = URL(fileURLWithPath: clonePath)
        let parentURL = cloneURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        // Clone or update the repository (with owner-specific token for authentication)
        let token = config.resolveToken(for: owner)
        let repoURL = "https://\(token)@github.com/\(owner)/\(repo).git"
        let branch = pr.head.ref

        if GitOperations.isGitRepo(at: clonePath) {
            // Update existing clone - also update remote URL to include token
            try await GitOperations.setRemoteURL(at: clonePath, url: repoURL)
            try await GitOperations.fetchAndReset(at: clonePath, branch: branch)
        } else {
            // Clone fresh
            try await GitOperations.clone(url: repoURL, to: clonePath, branch: branch)
        }

        // Build the PR URL
        let prURL = pr.htmlUrl

        // Launch Ghostty with Neovim
        try await launchGhostty(withPRURL: prURL, workingDirectory: clonePath)
    }

    /// Open a PR by URL
    /// - Parameter url: The GitHub PR URL
    public func openPRByURL(_ url: String) async throws {
        try await launchGhostty(withPRURL: url, workingDirectory: nil)
    }

    /// Open multiple PRs, each in a new Ghostty tab
    /// - Parameter prs: Array of (pr, owner, repo) tuples
    public func openAllPRs(_ prs: [(pr: PullRequest, owner: String, repo: String)]) async throws {
        guard !prs.isEmpty else { return }

        // Clone/update all repos first (in parallel for speed)
        var prPaths: [(pr: PullRequest, path: String)] = []

        await withTaskGroup(of: (PullRequest, String)?.self) { group in
            for (pr, owner, repo) in prs {
                group.addTask {
                    do {
                        let path = try await self.prepareRepo(pr: pr, owner: owner, repo: repo)
                        return (pr, path)
                    } catch {
                        print("Failed to prepare repo for PR #\(pr.number): \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let (pr, path) = result {
                    prPaths.append((pr: pr, path: path))
                }
            }
        }

        // Sort by PR number to maintain consistent order
        prPaths.sort { $0.pr.number < $1.pr.number }

        guard !prPaths.isEmpty else {
            throw GhosttyLauncherError.launchFailed(message: "No PRs could be prepared")
        }

        // Open first PR - this launches Ghostty
        let first = prPaths[0]
        try await launchGhostty(withPRURL: first.pr.htmlUrl, workingDirectory: first.path)

        // Wait a bit for Ghostty to start
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Open remaining PRs in new tabs using AppleScript
        for i in 1..<prPaths.count {
            let prInfo = prPaths[i]
            try await openInNewTab(prURL: prInfo.pr.htmlUrl, workingDirectory: prInfo.path)
            // Small delay between tabs
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }

    /// Prepare a repo for a PR (clone or update)
    private func prepareRepo(pr: PullRequest, owner: String, repo: String) async throws -> String {
        let cloneRoot = config.cloneRoot
        let expandedCloneRoot: String
        if cloneRoot.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expandedCloneRoot = home + cloneRoot.dropFirst()
        } else {
            expandedCloneRoot = cloneRoot
        }

        let clonePath = GitOperations.buildPRPath(cloneRoot: expandedCloneRoot, owner: owner, repo: repo, prNumber: pr.number)

        let fileManager = FileManager.default
        let cloneURL = URL(fileURLWithPath: clonePath)
        let parentURL = cloneURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        let token = config.resolveToken(for: owner)
        let repoURL = "https://\(token)@github.com/\(owner)/\(repo).git"
        let branch = pr.head.ref

        if GitOperations.isGitRepo(at: clonePath) {
            try await GitOperations.setRemoteURL(at: clonePath, url: repoURL)
            try await GitOperations.fetchAndReset(at: clonePath, branch: branch)
        } else {
            try await GitOperations.clone(url: repoURL, to: clonePath, branch: branch)
        }

        return clonePath
    }

    /// Open a PR in a new Ghostty tab using AppleScript
    private func openInNewTab(prURL: String, workingDirectory: String) async throws {
        // Write URL to temp file to avoid long command line issues with terminal wrapping
        try prURL.write(toFile: "/tmp/pr-review-url.txt", atomically: true, encoding: .utf8)

        let nvimPath = config.nvimPath
        let shellCommand = "cd '\(workingDirectory)' && \(nvimPath) -c 'Raccoon open'"

        // AppleScript to: activate Ghostty, send Cmd+T for new tab, type command, press Enter
        let script = """
        tell application "Ghostty"
            activate
        end tell

        delay 0.2

        tell application "System Events"
            tell process "Ghostty"
                keystroke "t" using command down
                delay 0.3
                keystroke "\(shellCommand.replacingOccurrences(of: "\"", with: "\\\""))"
                delay 0.1
                keystroke return
            end tell
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var errorInfo: NSDictionary?
        appleScript?.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            print("AppleScript error: \(error)")
        }
    }

    // MARK: - Private Helpers

    /// Launch Ghostty with Neovim configured for PR review
    private func launchGhostty(withPRURL prURL: String, workingDirectory: String?) async throws {
        // Get the Ghostty CLI binary path
        let ghosttyPath = config.ghosttyPath
        let ghosttyBinary: String
        if ghosttyPath.hasSuffix(".app") {
            ghosttyBinary = "\(ghosttyPath)/Contents/MacOS/ghostty"
        } else {
            ghosttyBinary = ghosttyPath
        }

        // Check if Ghostty exists
        guard FileManager.default.fileExists(atPath: ghosttyBinary) else {
            throw GhosttyLauncherError.ghosttyNotFound(path: ghosttyBinary)
        }

        // Write URL to temp file to avoid long command line issues with terminal wrapping
        try prURL.write(toFile: "/tmp/pr-review-url.txt", atomically: true, encoding: .utf8)

        // Build the shell command to execute inside Ghostty
        let nvimPath = config.nvimPath
        let shellCommand: String
        if let dir = workingDirectory {
            // cd to directory and run nvim with Raccoon command
            shellCommand = "cd '\(dir)' && \(nvimPath) -c 'Raccoon open'"
        } else {
            shellCommand = "\(nvimPath) -c 'Raccoon open'"
        }

        // Launch Ghostty using Process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghosttyBinary)
        process.arguments = ["-e", "/bin/zsh", "-c", shellCommand]

        do {
            try process.run()
            print("Launched Ghostty with PR: \(prURL)")
        } catch {
            throw GhosttyLauncherError.launchFailed(message: error.localizedDescription)
        }
    }
}

// MARK: - Errors

/// Errors that can occur when launching Ghostty
public enum GhosttyLauncherError: Error, CustomStringConvertible {
    case ghosttyNotFound(path: String)
    case launchFailed(message: String)
    case cloneFailed(message: String)

    public var description: String {
        switch self {
        case let .ghosttyNotFound(path):
            return "Ghostty not found at: \(path)"
        case let .launchFailed(message):
            return "Failed to launch Ghostty: \(message)"
        case let .cloneFailed(message):
            return "Failed to clone repository: \(message)"
        }
    }
}
