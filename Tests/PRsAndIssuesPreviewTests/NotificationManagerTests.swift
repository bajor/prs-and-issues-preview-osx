import Foundation
import XCTest
@testable import PRsAndIssuesPreview

// Note: NotificationManager singleton tests are skipped because
// UNUserNotificationCenter.current() requires app entitlements
// and crashes in test environments without them.

final class NotificationManagerCategoryTests: XCTestCase {

    func testCategoryRawValues() {
        XCTAssertEqual(NotificationManager.Category.newPR.rawValue, "NEW_PR")
        XCTAssertEqual(NotificationManager.Category.newCommits.rawValue, "NEW_COMMITS")
        XCTAssertEqual(NotificationManager.Category.newComments.rawValue, "NEW_COMMENTS")
        XCTAssertEqual(NotificationManager.Category.prMerged.rawValue, "PR_MERGED")
        XCTAssertEqual(NotificationManager.Category.prClosed.rawValue, "PR_CLOSED")
    }
}

final class NotificationManagerActionTests: XCTestCase {

    func testActionRawValues() {
        XCTAssertEqual(NotificationManager.Action.openPR.rawValue, "OPEN_PR")
        XCTAssertEqual(NotificationManager.Action.dismiss.rawValue, "DISMISS")
    }
}
