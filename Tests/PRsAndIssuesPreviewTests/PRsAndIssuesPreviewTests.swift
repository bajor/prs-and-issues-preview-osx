import XCTest
@testable import PRsAndIssuesPreview

final class PRReviewSystemTests: XCTestCase {

    func testVersionIsNotEmpty() {
        let version = getVersion()
        XCTAssertFalse(version.isEmpty, "Version should not be empty")
    }

    func testVersionFormat() {
        let version = getVersion()
        // Version should match semver format: X.Y.Z
        let pattern = #"^\d+\.\d+\.\d+$"#
        let regex = try? Regex(pattern)
        let match = version.wholeMatch(of: regex!)
        XCTAssertNotNil(match, "Version '\(version)' should match semver format X.Y.Z")
    }
}
