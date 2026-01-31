import Foundation

/// Service for cleaning up old PR clone directories
public final class CleanupService: @unchecked Sendable {
    // MARK: - Types

    /// State persisted to disk
    struct CleanupState: Codable {
        var lastCleanupDate: Date?
        var cleanedDirectories: [String]

        static let empty = CleanupState(lastCleanupDate: nil, cleanedDirectories: [])
    }

    /// Cleanup result
    public struct CleanupResult: Equatable, Sendable {
        public let deletedCount: Int
        public let freedBytes: Int64
        public let errors: [String]

        public var freedMB: Double {
            Double(freedBytes) / (1024 * 1024)
        }
    }

    // MARK: - Properties

    /// Root directory for PR clones
    private let cloneRoot: String

    /// Maximum age for directories in days
    private let maxAgeDays: Int

    /// State file path
    private let stateFilePath: String

    /// File manager
    private let fileManager = FileManager.default

    // MARK: - Initialization

    /// Initialize with configuration
    /// - Parameters:
    ///   - cloneRoot: Root directory for PR clones
    ///   - maxAgeDays: Maximum age in days before cleanup (default 30)
    public init(cloneRoot: String, maxAgeDays: Int = 30) {
        self.cloneRoot = cloneRoot
        self.maxAgeDays = maxAgeDays

        // State file is stored alongside clone root
        let stateDir = (cloneRoot as NSString).deletingLastPathComponent
        self.stateFilePath = (stateDir as NSString).appendingPathComponent("state.json")
    }

    /// Initialize from config
    public convenience init(config: Config) {
        self.init(cloneRoot: config.cloneRoot)
    }

    // MARK: - Public API

    /// Check if cleanup should run (hasn't run in last 24 hours)
    public func shouldRunCleanup() -> Bool {
        let state = loadState()
        guard let lastCleanup = state.lastCleanupDate else {
            return true // Never cleaned
        }

        let hoursSinceCleanup = Date().timeIntervalSince(lastCleanup) / 3600
        return hoursSinceCleanup >= 24
    }

    /// Run cleanup and remove directories older than maxAgeDays
    /// - Returns: CleanupResult with statistics
    public func runCleanup() -> CleanupResult {
        var deletedCount = 0
        var freedBytes: Int64 = 0
        var errors: [String] = []

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())!

        // Ensure clone root exists
        guard fileManager.fileExists(atPath: cloneRoot) else {
            saveState(CleanupState(lastCleanupDate: Date(), cleanedDirectories: []))
            return CleanupResult(deletedCount: 0, freedBytes: 0, errors: [])
        }

        // Iterate through owner directories
        do {
            let ownerDirs = try fileManager.contentsOfDirectory(atPath: cloneRoot)

            for ownerDir in ownerDirs {
                let ownerPath = (cloneRoot as NSString).appendingPathComponent(ownerDir)

                // Check if it's a directory
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: ownerPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                // Iterate through repo directories
                let repoDirs = try fileManager.contentsOfDirectory(atPath: ownerPath)

                for repoDir in repoDirs {
                    let repoPath = (ownerPath as NSString).appendingPathComponent(repoDir)

                    guard fileManager.fileExists(atPath: repoPath, isDirectory: &isDir), isDir.boolValue else {
                        continue
                    }

                    // Iterate through PR directories
                    let prDirs = try fileManager.contentsOfDirectory(atPath: repoPath)

                    for prDir in prDirs {
                        let prPath = (repoPath as NSString).appendingPathComponent(prDir)

                        guard fileManager.fileExists(atPath: prPath, isDirectory: &isDir), isDir.boolValue else {
                            continue
                        }

                        // Check modification date
                        if let modDate = getModificationDate(at: prPath), modDate < cutoffDate {
                            let size = getDirectorySize(at: prPath)
                            do {
                                try fileManager.removeItem(atPath: prPath)
                                deletedCount += 1
                                freedBytes += size
                            } catch {
                                errors.append("Failed to delete \(prPath): \(error.localizedDescription)")
                            }
                        }
                    }

                    // Clean up empty repo directories
                    if let contents = try? fileManager.contentsOfDirectory(atPath: repoPath), contents.isEmpty {
                        try? fileManager.removeItem(atPath: repoPath)
                    }
                }

                // Clean up empty owner directories
                if let contents = try? fileManager.contentsOfDirectory(atPath: ownerPath), contents.isEmpty {
                    try? fileManager.removeItem(atPath: ownerPath)
                }
            }
        } catch {
            errors.append("Failed to enumerate directories: \(error.localizedDescription)")
        }

        // Save state
        saveState(CleanupState(lastCleanupDate: Date(), cleanedDirectories: []))

        return CleanupResult(deletedCount: deletedCount, freedBytes: freedBytes, errors: errors)
    }

    /// Get list of directories that would be cleaned
    /// - Returns: Array of paths that would be deleted
    public func previewCleanup() -> [String] {
        var toDelete: [String] = []
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())!

        guard fileManager.fileExists(atPath: cloneRoot) else {
            return []
        }

        do {
            let ownerDirs = try fileManager.contentsOfDirectory(atPath: cloneRoot)

            for ownerDir in ownerDirs {
                let ownerPath = (cloneRoot as NSString).appendingPathComponent(ownerDir)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: ownerPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let repoDirs = try fileManager.contentsOfDirectory(atPath: ownerPath)

                for repoDir in repoDirs {
                    let repoPath = (ownerPath as NSString).appendingPathComponent(repoDir)
                    guard fileManager.fileExists(atPath: repoPath, isDirectory: &isDir), isDir.boolValue else {
                        continue
                    }

                    let prDirs = try fileManager.contentsOfDirectory(atPath: repoPath)

                    for prDir in prDirs {
                        let prPath = (repoPath as NSString).appendingPathComponent(prDir)
                        guard fileManager.fileExists(atPath: prPath, isDirectory: &isDir), isDir.boolValue else {
                            continue
                        }

                        if let modDate = getModificationDate(at: prPath), modDate < cutoffDate {
                            toDelete.append(prPath)
                        }
                    }
                }
            }
        } catch {
            // Return what we found so far
        }

        return toDelete
    }

    /// Get the last cleanup date
    public func lastCleanupDate() -> Date? {
        loadState().lastCleanupDate
    }

    // MARK: - Private Helpers

    /// Get modification date of a path
    private func getModificationDate(at path: String) -> Date? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }

    /// Get total size of a directory in bytes
    private func getDirectorySize(at path: String) -> Int64 {
        var size: Int64 = 0

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return 0
        }

        while let file = enumerator.nextObject() as? String {
            let filePath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: filePath) {
                size += (attrs[.size] as? Int64) ?? 0
            }
        }

        return size
    }

    /// Load state from disk
    private func loadState() -> CleanupState {
        guard fileManager.fileExists(atPath: stateFilePath) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CleanupState.self, from: data)
        } catch {
            return .empty
        }
    }

    /// Save state to disk
    private func saveState(_ state: CleanupState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(state)
            let url = URL(fileURLWithPath: stateFilePath)

            // Ensure parent directory exists
            let parentDir = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            try data.write(to: url)
        } catch {
            print("Failed to save cleanup state: \(error)")
        }
    }
}
