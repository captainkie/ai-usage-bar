import XCTest
@testable import AIUsageBar

final class AggregatorTests: XCTestCase {
    private func ev(_ project: String, _ model: String, daysAgo: Int, cost1kOut: Int) -> UsageEvent {
        let ts = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return UsageEvent(provider: .claude, timestamp: ts, model: model, project: project,
                          sessionId: "s\(daysAgo)", input: 0, output: cost1kOut, cacheWrite: 0, cacheRead: 0)
    }

    func testWindowFiltersByDay() {
        let events = [ev("p", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000),
                      ev("p", "claude-opus-4-8", daysAgo: 10, cost1kOut: 1000)]
        let today = CostAggregator.summary(events: events, window: .today)
        let week = CostAggregator.summary(events: events, window: .days7)
        let all = CostAggregator.summary(events: events, window: .all)
        XCTAssertEqual(today.byProject.count, 1)
        XCTAssertEqual(today.calls, 1)
        XCTAssertEqual(week.calls, 1)     // 10 days ago excluded from 7d
        XCTAssertEqual(all.calls, 2)
    }

    func testGroupsByProjectAndModel() {
        let events = [ev("a", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000),
                      ev("b", "claude-haiku-4-5", daysAgo: 0, cost1kOut: 1000)]
        let s = CostAggregator.summary(events: events, window: .all)
        XCTAssertEqual(Set(s.byProject.map(\.project)), ["a", "b"])
        XCTAssertEqual(Set(s.byModel.map(\.model)), ["claude-opus-4-8", "claude-haiku-4-5"])
        XCTAssertGreaterThan(s.totalCost, 0)
    }

    func testProjectFilter() {
        let events = [ev("a", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000),
                      ev("b", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000)]
        let s = CostAggregator.summary(events: events, window: .all, project: "a")
        XCTAssertEqual(s.calls, 1)
    }
}
