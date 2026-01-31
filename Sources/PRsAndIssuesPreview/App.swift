import AppKit
import Foundation

/// PR Review System - macOS Menu Bar Application
///
/// This application provides a menu bar interface for reviewing GitHub pull requests.
/// It polls configured repositories for PRs awaiting review and launches Ghostty + Neovim
/// for the actual review experience.

@main
struct PRReviewSystemApp {
    static func main() {
        // Create the application
        let app = NSApplication.shared

        // Create and set the delegate
        let delegate = AppDelegate()
        app.delegate = delegate

        // Keep a strong reference to the delegate
        // (otherwise it gets deallocated immediately)
        withExtendedLifetime(delegate) {
            // Run the application
            app.run()
        }
    }
}

// MARK: - Version Info

/// Returns the current version
public func getVersion() -> String {
    "0.12.0"
}
