import XCTest
@testable import AIUsageBar

final class PricingTests: XCTestCase {
    let p = Pricing.shared

    func testExactCost() {
        // Opus 4.8: $5 / $25 / $6.25 / $0.50 per 1M
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "claude-opus-4-8",
            project: "p", sessionId: "s",
            input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000)
        XCTAssertEqual(p.cost(for: e), 5 + 25 + 6.25 + 0.50, accuracy: 1e-6)
    }
    func testVersionSuffixResolves() {
        // "claude-opus-4-8[1m]" resolves to the opus-4-8 row
        XCTAssertGreaterThan(p.rate(for: "claude-opus-4-8[1m]")?.input ?? 0, 0)
    }
    func testUnknownModelIsZeroAndTracked() {
        var unpriced = Set<String>()
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "totally-unknown-x",
            project: "p", sessionId: "s", input: 100, output: 100, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(p.cost(for: e, unpriced: &unpriced), 0)
        XCTAssertTrue(unpriced.contains("totally-unknown-x"))
    }
}
