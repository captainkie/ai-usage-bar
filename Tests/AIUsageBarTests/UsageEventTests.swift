import XCTest
@testable import AIUsageBar

final class UsageEventTests: XCTestCase {
    func testProjectLabelIsLastPathComponent() {
        // project is the raw cwd path, so the label is a clean, reversible
        // last-path-component (a dir name with hyphens survives intact).
        XCTAssertEqual(projectLabel("/Users/x/Documents/work-hobby/ai-usage-bar"), "ai-usage-bar")
        XCTAssertEqual(projectLabel("/a/b"), "b")
        XCTAssertEqual(projectLabel("gemini:abcdef123456"), "gemini:abcdef")
    }
    func testTotalTokens() {
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "m", project: "p",
                           sessionId: "s", input: 10, output: 20, cacheWrite: 5, cacheRead: 3)
        XCTAssertEqual(e.totalTokens, 38)
    }
}
