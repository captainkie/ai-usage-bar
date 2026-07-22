import XCTest
@testable import AIUsageBar

final class BudgetTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(BudgetStatus(spent: 5, limit: 20).level, .normal)   // 25%
        XCTAssertEqual(BudgetStatus(spent: 17, limit: 20).level, .warn)    // 85%
        XCTAssertEqual(BudgetStatus(spent: 25, limit: 20).level, .over)    // 125%
    }
    func testAlertFiresOncePerThreshold() {
        // crossing 0.85 fires the 0.8 threshold once
        XCTAssertEqual(Budget.newlyCrossed(fraction: 0.85, alreadyFired: []), [0.8])
        XCTAssertEqual(Budget.newlyCrossed(fraction: 0.85, alreadyFired: [0.8]), [])
        // crossing 1.0 fires both remaining
        XCTAssertEqual(Budget.newlyCrossed(fraction: 1.2, alreadyFired: []), [0.8, 1.0])
        XCTAssertEqual(Budget.newlyCrossed(fraction: 0.5, alreadyFired: []), [])
    }
}
