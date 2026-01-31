import Foundation
import XCTest
@testable import PRsAndIssuesPreview

final class MenuBarControllerTests: XCTestCase {

    func testSharedInstanceExists() {
        let controller = MenuBarController.shared
        // If we got here, the shared instance exists
        XCTAssertTrue(type(of: controller) == MenuBarController.self)
    }

    func testUpdateBadgeZero() {
        let controller = MenuBarController.shared
        controller.updateBadge(count: 0)
        // No crash means success
    }

    func testUpdateBadgePositive() {
        let controller = MenuBarController.shared
        controller.updateBadge(count: 5)
        // No crash means success
    }

    func testRebuildMenu() {
        let controller = MenuBarController.shared
        controller.rebuildMenu()
        // No crash means success
    }

    func testUpdatePullRequestsEmpty() {
        let controller = MenuBarController.shared
        controller.updatePullRequests([:])
        // No crash means success
    }

    func testClearPullRequests() {
        let controller = MenuBarController.shared
        controller.clearPullRequests()
        // No crash means success
    }
}

final class NotificationNamesTests: XCTestCase {

    func testPrSelectedName() {
        let name = Notification.Name.prSelected
        XCTAssertEqual(name.rawValue, "PRReviewSystem.prSelected")
    }

    func testRefreshRequestedName() {
        let name = Notification.Name.refreshRequested
        XCTAssertEqual(name.rawValue, "PRReviewSystem.refreshRequested")
    }
}
