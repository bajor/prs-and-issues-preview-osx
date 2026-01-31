import Foundation

/// Configuration for PR Review System
public struct Config: Codable, Equatable, Sendable {
    /// GitHub personal access token (default/fallback token)
    public let githubToken: String

    /// GitHub username
    public let githubUsername: String

    /// List of repos to watch (format: "owner/repo")
    public let repos: [String]

    /// List of repos to exclude from watching (format: "owner/repo")
    public let excludedRepos: [String]

    /// Per-owner/org tokens (owner name -> token)
    /// If a repo's owner is in this map, use that token; otherwise use githubToken
    public let tokens: [String: String]

    /// Root directory for cloned PR repos
    public let cloneRoot: String

    /// Polling interval in seconds
    public let pollIntervalSeconds: Int

    /// Path to Ghostty.app
    public let ghosttyPath: String

    /// Path to nvim binary
    public let nvimPath: String

    /// Notification settings
    public let notifications: NotificationConfig

    /// Default configuration values
    static let defaults = Config(
        githubToken: "",
        githubUsername: "",
        repos: [],
        excludedRepos: [],
        tokens: [:],
        cloneRoot: "~/.local/share/pr-review/repos",
        pollIntervalSeconds: 300,
        ghosttyPath: "/Applications/Ghostty.app",
        nvimPath: "/opt/homebrew/bin/nvim",
        notifications: NotificationConfig.defaults
    )

    /// Resolve the appropriate token for a given owner/org
    /// Returns the owner-specific token if available, otherwise the default githubToken
    public func resolveToken(for owner: String) -> String {
        tokens[owner] ?? githubToken
    }

    /// Coding keys for JSON mapping (snake_case to camelCase)
    enum CodingKeys: String, CodingKey {
        case githubToken = "github_token"
        case githubUsername = "github_username"
        case repos
        case excludedRepos = "excluded_repos"
        case tokens
        case cloneRoot = "clone_root"
        case pollIntervalSeconds = "poll_interval_seconds"
        case ghosttyPath = "ghostty_path"
        case nvimPath = "nvim_path"
        case notifications
    }

    /// Custom decoder to handle optional fields with defaults
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        githubToken = try container.decode(String.self, forKey: .githubToken)
        githubUsername = try container.decode(String.self, forKey: .githubUsername)
        repos = try container.decodeIfPresent([String].self, forKey: .repos)
            ?? Config.defaults.repos
        excludedRepos = try container.decodeIfPresent([String].self, forKey: .excludedRepos)
            ?? Config.defaults.excludedRepos
        tokens = try container.decodeIfPresent([String: String].self, forKey: .tokens)
            ?? Config.defaults.tokens
        cloneRoot = try container.decodeIfPresent(String.self, forKey: .cloneRoot)
            ?? Config.defaults.cloneRoot
        pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds)
            ?? Config.defaults.pollIntervalSeconds
        ghosttyPath = try container.decodeIfPresent(String.self, forKey: .ghosttyPath)
            ?? Config.defaults.ghosttyPath
        nvimPath = try container.decodeIfPresent(String.self, forKey: .nvimPath)
            ?? Config.defaults.nvimPath
        notifications = try container.decodeIfPresent(NotificationConfig.self, forKey: .notifications)
            ?? NotificationConfig.defaults
    }

    /// Standard memberwise initializer
    init(
        githubToken: String,
        githubUsername: String,
        repos: [String],
        excludedRepos: [String],
        tokens: [String: String],
        cloneRoot: String,
        pollIntervalSeconds: Int,
        ghosttyPath: String,
        nvimPath: String,
        notifications: NotificationConfig
    ) {
        self.githubToken = githubToken
        self.githubUsername = githubUsername
        self.repos = repos
        self.excludedRepos = excludedRepos
        self.tokens = tokens
        self.cloneRoot = cloneRoot
        self.pollIntervalSeconds = pollIntervalSeconds
        self.ghosttyPath = ghosttyPath
        self.nvimPath = nvimPath
        self.notifications = notifications
    }

    /// Check if a repo should be excluded
    public func isExcluded(_ repo: String) -> Bool {
        excludedRepos.contains(repo)
    }
}

/// Notification configuration
public struct NotificationConfig: Codable, Equatable, Sendable {
    /// Notify on new commits
    public let newCommits: Bool

    /// Notify on new comments
    public let newComments: Bool

    /// Play sound with notifications
    public let sound: Bool

    /// Default values
    static let defaults = NotificationConfig(
        newCommits: true,
        newComments: true,
        sound: true
    )

    enum CodingKeys: String, CodingKey {
        case newCommits = "new_commits"
        case newComments = "new_comments"
        case sound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newCommits = try container.decodeIfPresent(Bool.self, forKey: .newCommits)
            ?? NotificationConfig.defaults.newCommits
        newComments = try container.decodeIfPresent(Bool.self, forKey: .newComments)
            ?? NotificationConfig.defaults.newComments
        sound = try container.decodeIfPresent(Bool.self, forKey: .sound)
            ?? NotificationConfig.defaults.sound
    }

    public init(newCommits: Bool = true, newComments: Bool = true, sound: Bool = true) {
        self.newCommits = newCommits
        self.newComments = newComments
        self.sound = sound
    }
}

/// Configuration validation errors
enum ConfigError: Error, Equatable, CustomStringConvertible {
    case fileNotFound(path: String)
    case invalidJSON(message: String)
    case missingRequiredField(name: String)
    case invalidRepoFormat(repo: String)

    var description: String {
        switch self {
        case let .fileNotFound(path):
            "Config file not found: \(path)"
        case let .invalidJSON(message):
            "Invalid JSON: \(message)"
        case let .missingRequiredField(name):
            "\(name) is required"
        case let .invalidRepoFormat(repo):
            "Invalid repo format: '\(repo)' (expected 'owner/repo')"
        }
    }
}

/// Configuration loader
enum ConfigLoader {
    /// Default config file path
    static var configPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/pr-review/config.json"
    }

    /// Expand tilde in paths
    static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + path.dropFirst()
        }
        return path
    }

    /// Validate repo format (owner/repo)
    static func isValidRepoFormat(_ repo: String) -> Bool {
        let pattern = #"^[\w\-_.]+/[\w\-_.]+$"#
        return repo.range(of: pattern, options: .regularExpression) != nil
    }

    /// Load and validate configuration from file
    static func load(from path: String? = nil) throws -> Config {
        let configPath = path ?? self.configPath

        // Check if file exists
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw ConfigError.fileNotFound(path: configPath)
        }

        // Read file
        let url = URL(fileURLWithPath: configPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.fileNotFound(path: configPath)
        }

        // Parse JSON
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch let error as DecodingError {
            switch error {
            case let .keyNotFound(key, _):
                throw ConfigError.missingRequiredField(name: key.stringValue)
            default:
                throw ConfigError.invalidJSON(message: error.localizedDescription)
            }
        } catch {
            throw ConfigError.invalidJSON(message: error.localizedDescription)
        }

        // Validate
        try validate(config)

        // Return config with expanded paths
        return Config(
            githubToken: config.githubToken,
            githubUsername: config.githubUsername,
            repos: config.repos,
            excludedRepos: config.excludedRepos,
            tokens: config.tokens,
            cloneRoot: expandPath(config.cloneRoot),
            pollIntervalSeconds: config.pollIntervalSeconds,
            ghosttyPath: expandPath(config.ghosttyPath),
            nvimPath: expandPath(config.nvimPath),
            notifications: config.notifications
        )
    }

    /// Validate configuration
    private static func validate(_ config: Config) throws {
        if config.githubToken.isEmpty && config.tokens.isEmpty {
            throw ConfigError.missingRequiredField(name: "github_token or tokens")
        }

        if config.githubUsername.isEmpty {
            throw ConfigError.missingRequiredField(name: "github_username")
        }

        // Validate repo format if repos are specified
        for repo in config.repos {
            if !isValidRepoFormat(repo) {
                throw ConfigError.invalidRepoFormat(repo: repo)
            }
        }

        // Validate excluded repo format
        for repo in config.excludedRepos {
            if !isValidRepoFormat(repo) {
                throw ConfigError.invalidRepoFormat(repo: repo)
            }
        }
    }
}
