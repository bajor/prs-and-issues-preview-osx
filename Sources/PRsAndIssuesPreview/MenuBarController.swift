import AppKit
import Foundation

/// PR with additional display info
public struct PRDisplayInfo {
    public let pr: PullRequest
    public var lastCommitMessage: String?
    public var checkStatus: CheckStatus?
    public var lastCheckedSHA: String?  // Track which SHA we last checked

    public init(pr: PullRequest, lastCommitMessage: String? = nil, checkStatus: CheckStatus? = nil) {
        self.pr = pr
        self.lastCommitMessage = lastCommitMessage
        self.checkStatus = checkStatus
        self.lastCheckedSHA = pr.head.sha
    }
}

/// Issue display info (simpler than PRDisplayInfo - no commits/checks)
public struct IssueDisplayInfo {
    public let issue: Issue

    public init(issue: Issue) {
        self.issue = issue
    }
}

/// Manages the menu bar status item and menu
public final class MenuBarController: NSObject {
    // MARK: - Properties

    /// The status item displayed in the menu bar
    private var statusItem: NSStatusItem?

    /// The menu displayed when clicking the status item
    private var menu: NSMenu?

    /// Current pull requests grouped by repository (with display info)
    private var pullRequests: [String: [PRDisplayInfo]] = [:]

    /// Current issues grouped by repository
    private var issues: [String: [IssueDisplayInfo]] = [:]

    /// Badge count (number of PRs needing review)
    private var badgeCount: Int = 0

    /// Shared instance
    public static let shared = MenuBarController()

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Set up the menu bar status item
    public func setup() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure button
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Set initial display
        updateStatusDisplay()

        // Create initial menu
        rebuildMenu()
    }

    // MARK: - Status Image

    /// Update the status item display with PR text and badge
    private func updateStatusDisplay() {
        guard let button = statusItem?.button else { return }

        // Create attributed string for "PR" text
        let prText = badgeCount > 0 ? "PR \(badgeCount)" : "PR"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.controlTextColor
        ]
        button.attributedTitle = NSAttributedString(string: prText, attributes: attributes)
        button.image = nil
    }

    /// Update the status item with badge count
    public func updateBadge(count: Int) {
        badgeCount = count
        updateStatusDisplay()
    }

    // MARK: - Menu Actions

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click shows context menu
            showMenu()
        } else {
            // Left-click also shows menu (or could toggle popover)
            showMenu()
        }
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil // Reset to allow custom click handling
    }

    // MARK: - Menu Building

    /// Rebuild the menu with current pull requests
    public func rebuildMenu() {
        let newMenu = NSMenu()

        // Header
        let headerItem = NSMenuItem(title: "PR Review System", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        newMenu.addItem(headerItem)

        newMenu.addItem(NSMenuItem.separator())

        // Pull requests grouped by repo
        if pullRequests.isEmpty {
            let noPRsItem = NSMenuItem(title: "No PRs awaiting review", action: nil, keyEquivalent: "")
            noPRsItem.isEnabled = false
            newMenu.addItem(noPRsItem)
        } else {
            for (repo, prInfos) in pullRequests.sorted(by: { $0.key < $1.key }) {
                // Repository header
                let repoItem = NSMenuItem(title: repo, action: nil, keyEquivalent: "")
                repoItem.isEnabled = false
                if let font = NSFont.boldSystemFont(ofSize: 12) as NSFont? {
                    repoItem.attributedTitle = NSAttributedString(
                        string: repo,
                        attributes: [.font: font]
                    )
                }
                newMenu.addItem(repoItem)

                // PR items
                for prInfo in prInfos {
                    let prItem = createPRMenuItem(prInfo: prInfo)
                    newMenu.addItem(prItem)
                }

                newMenu.addItem(NSMenuItem.separator())
            }
        }

        // Issues section
        if !issues.isEmpty {
            // Issues header
            let issuesHeader = NSMenuItem(title: "Issues", action: nil, keyEquivalent: "")
            issuesHeader.isEnabled = false
            if let font = NSFont.boldSystemFont(ofSize: 13) as NSFont? {
                issuesHeader.attributedTitle = NSAttributedString(
                    string: "Issues",
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]
                )
            }
            newMenu.addItem(issuesHeader)
            newMenu.addItem(NSMenuItem.separator())

            for (repo, issueInfos) in issues.sorted(by: { $0.key < $1.key }) {
                // Repository header
                let repoItem = NSMenuItem(title: repo, action: nil, keyEquivalent: "")
                repoItem.isEnabled = false
                if let font = NSFont.boldSystemFont(ofSize: 12) as NSFont? {
                    repoItem.attributedTitle = NSAttributedString(
                        string: repo,
                        attributes: [.font: font]
                    )
                }
                newMenu.addItem(repoItem)

                // Issue items
                for issueInfo in issueInfos {
                    let issueItem = createIssueMenuItem(issueInfo: issueInfo)
                    newMenu.addItem(issueItem)
                }

                newMenu.addItem(NSMenuItem.separator())
            }
        }

        // Actions
        newMenu.addItem(NSMenuItem.separator())

        // Open All PRs option (only show if there are PRs)
        let totalPRCount = pullRequests.values.reduce(0) { $0 + $1.count }
        if totalPRCount > 0 {
            let openAllItem = NSMenuItem(title: "Open All PRs (\(totalPRCount))", action: #selector(openAllClicked), keyEquivalent: "a")
            openAllItem.target = self
            newMenu.addItem(openAllItem)
        }

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        newMenu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        newMenu.addItem(quitItem)

        menu = newMenu
    }

    /// Create a menu item for a pull request with commit info and check status
    private func createPRMenuItem(prInfo: PRDisplayInfo) -> NSMenuItem {
        let pr = prInfo.pr

        // Build check status string
        let checkStatusStr = prInfo.checkStatus?.displayString ?? ""
        let checkStatusSuffix = checkStatusStr.isEmpty ? "" : "  \(checkStatusStr)"

        // Build attributed title with PR title bold, commit message below in gray
        let titleText = "  #\(pr.number): \(pr.title)\(checkStatusSuffix)\n"
        let commitText = "       \(prInfo.lastCommitMessage ?? "Loading...")"

        let fullText = NSMutableAttributedString()

        // PR title in bold
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        fullText.append(NSAttributedString(string: titleText, attributes: titleAttrs))

        // Commit message in gray, smaller
        let commitAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        fullText.append(NSAttributedString(string: commitText, attributes: commitAttrs))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = fullText

        // Create submenu with PR description and actions
        let submenu = NSMenu()

        // PR description in a scrollable view
        let description = pr.body ?? "No description provided."
        let cleanDescription = markdownToPlainText(description)

        // Create scrollable description view
        let descMenuItem = NSMenuItem()
        let descView = createScrollableDescriptionView(text: cleanDescription)
        descMenuItem.view = descView
        submenu.addItem(descMenuItem)

        submenu.addItem(NSMenuItem.separator())

        // Check status info if available
        if let status = prInfo.checkStatus, status.totalCount > 0 {
            let statusText = "Checks: \(status.passedCount)/\(status.totalCount) passed"
            let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            var statusStr = statusText
            if status.failedCount > 0 {
                statusStr += ", \(status.failedCount) failed"
            }
            if status.pendingCount > 0 {
                statusStr += ", \(status.pendingCount) pending"
            }
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            statusItem.attributedTitle = NSAttributedString(string: statusStr, attributes: statusAttrs)
            submenu.addItem(statusItem)
            submenu.addItem(NSMenuItem.separator())
        }

        // Open in Raccoon plugin in Neovim
        let openItem = NSMenuItem(title: "Open in Raccoon", action: #selector(prClicked(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = pr
        submenu.addItem(openItem)

        // Go to GitHub action
        let githubItem = NSMenuItem(title: "Go to GitHub", action: #selector(openInGitHub(_:)), keyEquivalent: "")
        githubItem.target = self
        githubItem.representedObject = pr.htmlUrl
        submenu.addItem(githubItem)

        item.submenu = submenu
        return item
    }

    /// Create a menu item for an issue with description hover
    private func createIssueMenuItem(issueInfo: IssueDisplayInfo) -> NSMenuItem {
        let issue = issueInfo.issue

        // Build attributed title with issue number and title
        let titleText = "  #\(issue.number): \(issue.title)"

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: titleText, attributes: titleAttrs)

        // Create submenu with issue description and Go to GitHub action
        let submenu = NSMenu()

        // Issue description in a scrollable view
        let description = issue.body ?? "No description provided."
        let cleanDescription = markdownToPlainText(description)

        // Create scrollable description view
        let descMenuItem = NSMenuItem()
        let descView = createScrollableDescriptionView(text: cleanDescription)
        descMenuItem.view = descView
        submenu.addItem(descMenuItem)

        submenu.addItem(NSMenuItem.separator())

        // Go to GitHub action
        let githubItem = NSMenuItem(title: "Go to GitHub", action: #selector(openInGitHub(_:)), keyEquivalent: "")
        githubItem.target = self
        githubItem.representedObject = issue.htmlUrl
        submenu.addItem(githubItem)

        item.submenu = submenu
        return item
    }

    /// Convert basic markdown to plain text
    private func markdownToPlainText(_ markdown: String) -> String {
        var text = markdown

        // Remove code blocks
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "[code block]", options: .regularExpression)
        text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)

        // Remove headers (keep text)
        text = text.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)

        // Remove bold/italic markers
        text = text.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)

        // Convert links [text](url) to just text
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)

        // Remove image syntax
        text = text.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]+\\)", with: "[image: $1]", options: .regularExpression)

        // Convert bullet points
        text = text.replacingOccurrences(of: "^[\\*\\-\\+]\\s+", with: "• ", options: .regularExpression)

        // Convert numbered lists
        text = text.replacingOccurrences(of: "^\\d+\\.\\s+", with: "• ", options: .regularExpression)

        // Remove horizontal rules
        text = text.replacingOccurrences(of: "^[\\-\\*_]{3,}$", with: "───", options: .regularExpression)

        // Clean up multiple newlines
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // Trim whitespace
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    /// Wrap text to fit within a certain width, returning lines
    private func wrapText(_ text: String, maxWidth: Int, maxLines: Int) -> [String] {
        var lines: [String] = []
        let paragraphs = text.components(separatedBy: "\n")

        for paragraph in paragraphs {
            if paragraph.isEmpty {
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                continue
            }

            let words = paragraph.split(separator: " ", omittingEmptySubsequences: false)
            var currentLine = ""

            for word in words {
                let wordStr = String(word)
                if currentLine.isEmpty {
                    currentLine = wordStr
                } else if currentLine.count + 1 + wordStr.count <= maxWidth {
                    currentLine += " " + wordStr
                } else {
                    lines.append(currentLine)
                    currentLine = wordStr
                    if lines.count >= maxLines - 1 {
                        break
                    }
                }
            }

            if !currentLine.isEmpty {
                lines.append(currentLine)
            }

            if lines.count >= maxLines {
                break
            }
        }

        // Truncate if needed
        if lines.count >= maxLines {
            lines = Array(lines.prefix(maxLines - 1))
            lines.append("...")
        }

        // Remove trailing empty lines
        while lines.last == "" {
            lines.removeLast()
        }

        return lines.isEmpty ? ["No description provided."] : lines
    }

    @objc private func openInGitHub(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Create a scrollable view for PR description
    private func createScrollableDescriptionView(text: String) -> NSView {
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 300
        let padding: CGFloat = 10

        // Create scroll view first with fixed frame
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: maxHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Create text view with proper configuration
        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: padding, height: padding)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: contentSize.width - padding * 2, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        // Build attributed string with header and description
        let fullText = NSMutableAttributedString()

        // Header "Description"
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6)
        ]
        fullText.append(NSAttributedString(string: "Description\n\n", attributes: headerAttrs))

        // Description body - explicitly white for dark menu
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white
        ]
        fullText.append(NSAttributedString(string: text, attributes: bodyAttrs))

        textView.textStorage?.setAttributedString(fullText)

        // Calculate actual content height
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 100
        let finalHeight = min(usedHeight + padding * 3, maxHeight)

        // Update frames
        scrollView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: finalHeight)
        scrollView.documentView = textView

        return scrollView
    }

    /// Truncate a string to a maximum length
    private func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        return String(string.prefix(maxLength - 3)) + "..."
    }

    // MARK: - Menu Actions

    @objc private func prClicked(_ sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PullRequest else { return }
        NotificationCenter.default.post(
            name: .prSelected,
            object: nil,
            userInfo: ["pr": pr]
        )
    }

    @objc private func refreshClicked() {
        NotificationCenter.default.post(name: .refreshRequested, object: nil)
    }

    @objc private func openAllClicked() {
        // Collect all PRs
        var allPRs: [PullRequest] = []
        for (_, prInfos) in pullRequests.sorted(by: { $0.key < $1.key }) {
            for prInfo in prInfos {
                allPRs.append(prInfo.pr)
            }
        }
        guard !allPRs.isEmpty else { return }
        NotificationCenter.default.post(
            name: .openAllPRs,
            object: nil,
            userInfo: ["prs": allPRs]
        )
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Data Updates

    /// Update the pull requests displayed in the menu
    public func updatePullRequests(_ prs: [String: [PRDisplayInfo]]) {
        pullRequests = prs
        rebuildMenu()

        // Update badge count
        let totalCount = prs.values.reduce(0) { $0 + $1.count }
        updateBadge(count: totalCount)
    }

    /// Convenience method to update with plain PRs (will show "Loading..." for commits)
    public func updatePullRequestsSimple(_ prs: [String: [PullRequest]]) {
        var displayInfos: [String: [PRDisplayInfo]] = [:]
        for (repo, prList) in prs {
            displayInfos[repo] = prList.map { PRDisplayInfo(pr: $0) }
        }
        updatePullRequests(displayInfos)
    }

    /// Update the issues displayed in the menu
    public func updateIssues(_ newIssues: [String: [IssueDisplayInfo]]) {
        issues = newIssues
        rebuildMenu()
    }

    /// Convenience method to update with plain Issues
    public func updateIssuesSimple(_ newIssues: [String: [Issue]]) {
        var displayInfos: [String: [IssueDisplayInfo]] = [:]
        for (repo, issueList) in newIssues {
            displayInfos[repo] = issueList.map { IssueDisplayInfo(issue: $0) }
        }
        updateIssues(displayInfos)
    }

    /// Update the commit message for a specific PR
    public func updateCommitMessage(forPR prNumber: Int, inRepo repo: String, message: String) {
        guard var prInfos = pullRequests[repo] else { return }
        if let index = prInfos.firstIndex(where: { $0.pr.number == prNumber }) {
            prInfos[index].lastCommitMessage = message
            pullRequests[repo] = prInfos
            rebuildMenu()
        }
    }

    /// Update the check status for a specific PR
    public func updateCheckStatus(forPR prNumber: Int, inRepo repo: String, status: CheckStatus, sha: String) {
        guard var prInfos = pullRequests[repo] else { return }
        if let index = prInfos.firstIndex(where: { $0.pr.number == prNumber }) {
            prInfos[index].checkStatus = status
            prInfos[index].lastCheckedSHA = sha
            pullRequests[repo] = prInfos
            rebuildMenu()
        }
    }

    /// Get all PRs that have pending checks (need polling)
    public func getPRsWithPendingChecks() -> [(repo: String, pr: PullRequest, sha: String)] {
        var result: [(repo: String, pr: PullRequest, sha: String)] = []
        for (repo, prInfos) in pullRequests {
            for prInfo in prInfos {
                if let status = prInfo.checkStatus, status.isRunning {
                    result.append((repo: repo, pr: prInfo.pr, sha: prInfo.pr.head.sha))
                }
            }
        }
        return result
    }

    /// Get all PRs that need check status fetched (no status yet or SHA changed)
    public func getPRsNeedingCheckStatus() -> [(repo: String, pr: PullRequest)] {
        var result: [(repo: String, pr: PullRequest)] = []
        for (repo, prInfos) in pullRequests {
            for prInfo in prInfos {
                // Need to fetch if no status or if SHA changed (new commits)
                if prInfo.checkStatus == nil || prInfo.lastCheckedSHA != prInfo.pr.head.sha {
                    result.append((repo: repo, pr: prInfo.pr))
                }
            }
        }
        return result
    }

    /// Clear all pull requests
    public func clearPullRequests() {
        pullRequests = [:]
        rebuildMenu()
        updateBadge(count: 0)
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted when a PR is selected from the menu
    static let prSelected = Notification.Name("PRReviewSystem.prSelected")

    /// Posted when refresh is requested
    static let refreshRequested = Notification.Name("PRReviewSystem.refreshRequested")

    /// Posted when "Open All PRs" is clicked
    static let openAllPRs = Notification.Name("PRReviewSystem.openAllPRs")
}
