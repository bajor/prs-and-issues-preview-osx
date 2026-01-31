import AppKit
import Foundation
import UserNotifications

/// Manages system notifications for PR updates
public final class NotificationManager: NSObject, @unchecked Sendable {
    // MARK: - Types

    /// Notification categories
    public enum Category: String {
        case newPR = "NEW_PR"
        case newCommits = "NEW_COMMITS"
        case newComments = "NEW_COMMENTS"
        case prMerged = "PR_MERGED"
        case prClosed = "PR_CLOSED"
    }

    /// Notification actions
    public enum Action: String {
        case openPR = "OPEN_PR"
        case dismiss = "DISMISS"
    }

    // MARK: - Properties

    /// Shared instance
    public static let shared = NotificationManager()

    /// Notification center (lazily initialized on first use)
    private var _center: UNUserNotificationCenter?
    private var _centerInitialized = false

    /// Whether sound is enabled
    public var soundEnabled: Bool = true

    /// Callback when user clicks on a notification to open a PR
    public var onOpenPR: ((String) -> Void)?

    /// Whether running in a test environment
    private var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Whether running as a standalone executable (not in an app bundle)
    private var isStandaloneExecutable: Bool {
        // UNUserNotificationCenter requires a proper .app bundle
        // If we're running from a directory like ~/.local/bin/, we don't have a bundle
        let bundleURL = Bundle.main.bundleURL
        return !bundleURL.pathExtension.lowercased().hasSuffix("app") &&
               Bundle.main.bundleIdentifier == nil
    }

    /// Whether notifications are available (determined on first use)
    private var notificationsAvailable: Bool = true

    // MARK: - Initialization

    private override init() {
        super.init()
        // Don't initialize anything notification-related here
        // It will be done lazily on first notification attempt
    }

    /// Get or initialize the notification center
    private func getCenter() -> UNUserNotificationCenter? {
        if _centerInitialized {
            return _center
        }
        _centerInitialized = true

        // Skip notification center if running in test environment or standalone executable
        if isTestEnvironment || isStandaloneExecutable {
            notificationsAvailable = false
            if isStandaloneExecutable {
                print("Running as standalone executable - system notifications disabled (custom sound still works)")
            }
            return nil
        }

        // Initialize notification center
        _center = UNUserNotificationCenter.current()
        setupCategories()
        return _center
    }

    // MARK: - Public API

    /// Request notification permissions
    public func requestPermissions() async -> Bool {
        guard let center = getCenter() else { return false }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Failed to request notification permissions: \(error)")
            return false
        }
    }

    /// Check if notifications are authorized
    public func isAuthorized() async -> Bool {
        guard let center = getCenter() else { return false }
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// Send a notification for a new PR
    public func notifyNewPR(title: String, repo: String, author: String, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "New PR in \(repo)"
        content.subtitle = "by \(author)"
        content.body = title
        content.categoryIdentifier = Category.newPR.rawValue
        content.userInfo = ["prURL": prURL]

        if soundEnabled {
            content.sound = .default
        }

        sendNotification(content: content, identifier: "new-pr-\(prURL.hashValue)")
    }

    /// Send a notification for new commits
    public func notifyNewCommits(prTitle: String, repo: String, prNumber: Int, commitCount: Int, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "New commits in \(repo)"
        content.subtitle = "PR #\(prNumber)"
        content.body = "\(commitCount) new commit\(commitCount == 1 ? "" : "s") in: \(prTitle)"
        content.categoryIdentifier = Category.newCommits.rawValue
        content.userInfo = ["prURL": prURL]

        if soundEnabled {
            content.sound = .default
        }

        sendNotification(content: content, identifier: "new-commits-\(prURL.hashValue)")
    }

    /// Send a notification for new comments
    public func notifyNewComments(prTitle: String, repo: String, prNumber: Int, commentCount: Int, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "New comments in \(repo)"
        content.subtitle = "PR #\(prNumber)"
        content.body = "\(commentCount) new comment\(commentCount == 1 ? "" : "s") on: \(prTitle)"
        content.categoryIdentifier = Category.newComments.rawValue
        content.userInfo = ["prURL": prURL]

        if soundEnabled {
            content.sound = .default
        }

        sendNotification(content: content, identifier: "new-comments-\(prURL.hashValue)")
    }

    /// Send a notification for PR status change
    public func notifyPRStatusChange(prTitle: String, repo: String, prNumber: Int, status: String, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "PR \(status) in \(repo)"
        content.subtitle = "PR #\(prNumber)"
        content.body = prTitle
        content.categoryIdentifier = status == "merged" ? Category.prMerged.rawValue : Category.prClosed.rawValue
        content.userInfo = ["prURL": prURL]

        if soundEnabled {
            content.sound = .default
        }

        sendNotification(content: content, identifier: "pr-status-\(prURL.hashValue)")
    }

    /// Send a generic notification
    public func notify(title: String, body: String, subtitle: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }

        if soundEnabled {
            content.sound = .default
        }

        sendNotification(content: content, identifier: UUID().uuidString)
    }

    /// Clear all delivered notifications
    public func clearAll() {
        guard let center = getCenter() else { return }
        center.removeAllDeliveredNotifications()
    }

    /// Clear notifications for a specific PR
    public func clearForPR(url: String) {
        guard let center = getCenter() else { return }
        center.getDeliveredNotifications { notifications in
            let toRemove = notifications.filter { notification in
                notification.request.content.userInfo["prURL"] as? String == url
            }.map { $0.request.identifier }

            center.removeDeliveredNotifications(withIdentifiers: toRemove)
        }
    }

    // MARK: - Private Methods

    /// Setup notification categories and actions
    private func setupCategories() {
        guard let center = _center else { return }

        let openAction = UNNotificationAction(
            identifier: Action.openPR.rawValue,
            title: "Open PR",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: Action.dismiss.rawValue,
            title: "Dismiss",
            options: []
        )

        let categories = [Category.newPR, Category.newCommits, Category.newComments, Category.prMerged, Category.prClosed].map { category in
            UNNotificationCategory(
                identifier: category.rawValue,
                actions: [openAction, dismissAction],
                intentIdentifiers: [],
                options: []
            )
        }

        center.setNotificationCategories(Set(categories))
        center.delegate = self
    }

    /// Send a notification
    private func sendNotification(content: UNMutableNotificationContent, identifier: String) {
        guard let center = getCenter() else { return }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Immediate delivery
        )

        center.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }

}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    /// Handle notification action
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Action.openPR.rawValue, UNNotificationDefaultActionIdentifier:
            if let prURL = userInfo["prURL"] as? String {
                onOpenPR?(prURL)
            }
        case Action.dismiss.rawValue:
            // Just dismiss, nothing to do
            break
        default:
            break
        }

        completionHandler()
    }
}
