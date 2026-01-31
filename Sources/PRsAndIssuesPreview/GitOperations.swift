import Foundation

/// Git operations for cloning and managing PR repositories
enum GitOperations {
    /// Clone a repository
    /// - Parameters:
    ///   - url: Repository URL
    ///   - path: Destination path
    ///   - branch: Optional branch to checkout
    static func clone(url: String, to path: String, branch: String? = nil) async throws {
        // Ensure parent directory exists
        let parentPath = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentPath, withIntermediateDirectories: true)

        var args = ["clone", "--depth", "1"]
        if let branch {
            args.append(contentsOf: ["--branch", branch])
        }
        args.append(contentsOf: [url, path])

        try await runGit(args: args)
    }

    /// Fetch and reset to a remote branch
    /// - Parameters:
    ///   - path: Repository path
    ///   - branch: Branch name
    static func fetchAndReset(at path: String, branch: String) async throws {
        // Fetch
        try await runGit(args: ["fetch", "origin", branch], cwd: path)

        // Try to checkout the branch
        do {
            try await runGit(args: ["checkout", branch], cwd: path)
        } catch {
            // Branch might not exist locally, try creating it
            do {
                try await runGit(args: ["checkout", "-b", branch, "origin/\(branch)"], cwd: path)
            } catch {
                // Already exists, just continue to reset
            }
        }

        // Reset to remote
        try await runGit(args: ["reset", "--hard", "origin/\(branch)"], cwd: path)
    }

    /// Get the current branch name
    /// - Parameter path: Repository path
    /// - Returns: Current branch name
    static func getCurrentBranch(at path: String) async throws -> String {
        let output = try await runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the current commit SHA
    /// - Parameter path: Repository path
    /// - Returns: Current commit SHA
    static func getCurrentSHA(at path: String) async throws -> String {
        let output = try await runGit(args: ["rev-parse", "HEAD"], cwd: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if a path is a git repository
    /// - Parameter path: Path to check
    /// - Returns: True if path is a git repository
    static func isGitRepo(at path: String) -> Bool {
        let gitDir = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Get the remote URL for a repository
    /// - Parameter path: Repository path
    /// - Returns: Remote URL
    static func getRemoteURL(at path: String) async throws -> String {
        let output = try await runGit(args: ["remote", "get-url", "origin"], cwd: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Set the remote URL for a repository
    /// - Parameters:
    ///   - path: Repository path
    ///   - url: New remote URL
    static func setRemoteURL(at path: String, url: String) async throws {
        try await runGit(args: ["remote", "set-url", "origin", url], cwd: path)
    }

    /// Build the clone path for a PR
    /// - Parameters:
    ///   - cloneRoot: Root directory for clones
    ///   - owner: Repository owner
    ///   - repo: Repository name
    ///   - prNumber: PR number
    /// - Returns: Full path for the PR clone
    static func buildPRPath(cloneRoot: String, owner: String, repo: String, prNumber: Int) -> String {
        let root = cloneRoot.hasSuffix("/") ? String(cloneRoot.dropLast()) : cloneRoot
        return "\(root)/\(owner)/\(repo)/pr-\(prNumber)"
    }

    // MARK: - Private Helpers

    /// Run a git command and return the output
    @discardableResult
    private static func runGit(args: [String], cwd: String? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed(
                command: "git \(args.joined(separator: " "))",
                exitCode: Int(process.terminationStatus),
                message: errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

/// Git operation errors
enum GitError: Error, Equatable, CustomStringConvertible {
    case commandFailed(command: String, exitCode: Int, message: String)
    case notARepository(path: String)

    var description: String {
        switch self {
        case let .commandFailed(command, exitCode, message):
            "Git command failed: \(command) (exit \(exitCode)): \(message)"
        case let .notARepository(path):
            "Not a git repository: \(path)"
        }
    }
}
