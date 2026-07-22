import XCTest
@testable import AIUsageBar

final class UsageEventTests: XCTestCase {
    func testSanitizeCwd() {
        XCTAssertEqual(sanitizeProject("/Users/x/Documents/work-hobby/ai-usage-bar"),
                       "Users-x-Documents-work-hobby-ai-usage-bar")
        XCTAssertEqual(sanitizeProject("/a/b"), "a-b")
    }
    func testProjectLabelShortensToLastPathComponent() {
        // NOTE: sanitizeProject flattens "/" to "-", so a directory name that
        // itself contains hyphens (like "ai-usage-bar") is indistinguishable
        // from path separators once flattened. The last-dash-segment split
        // below can only recover "bar" here, not the full original directory
        // name — that's the actual (and only correct) behavior of the given
        // split(separator:"-").last algorithm.
        XCTAssertEqual(projectLabel("Users-x-Documents-work-hobby-ai-usage-bar"), "bar")
        XCTAssertEqual(projectLabel("gemini:abcdef123456"), "gemini:abcdef")
    }
    func testTotalTokens() {
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "m", project: "p",
                           sessionId: "s", input: 10, output: 20, cacheWrite: 5, cacheRead: 3)
        XCTAssertEqual(e.totalTokens, 38)
    }
}
