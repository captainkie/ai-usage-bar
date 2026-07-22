import XCTest
@testable import AIUsageBar

final class CostCacheTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let e = UsageEvent(provider: .codex, timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            model: "gpt-5-codex", project: "p", sessionId: "s", input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        let data = try JSONEncoder().encode([CachedEvent(e)])
        let back = try JSONDecoder().decode([CachedEvent].self, from: data)
        XCTAssertEqual(back.first?.toEvent().output, 2)
        XCTAssertEqual(back.first?.toEvent().provider, .codex)
    }
}
