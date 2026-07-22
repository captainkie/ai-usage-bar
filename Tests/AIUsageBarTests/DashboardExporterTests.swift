import XCTest
@testable import AIUsageBar

final class DashboardExporterTests: XCTestCase {
    func testHtmlIsSelfContainedAndEmbedsData() {
        let events = [UsageEvent(provider: .claude, timestamp: Date(), model: "claude-opus-4-8",
            project: "/Users/x/ai-usage-bar", sessionId: "s", input: 10, output: 20, cacheWrite: 0, cacheRead: 0)]
        let html = DashboardExporter.html(events: events, budgets: ["/Users/x/ai-usage-bar": 20])
        XCTAssertTrue(html.contains("__AUB_DATA__"))
        XCTAssertTrue(html.contains("ai-usage-bar"))         // project label present
        XCTAssertFalse(html.contains("http://"))             // no external requests
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("<script src"))
    }
}
