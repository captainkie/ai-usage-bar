import XCTest
@testable import AIUsageBar

final class BudgetSettingsStoreTests: XCTestCase {
    func testBudgetRoundTrip() {
        let d = UserDefaults(suiteName: "aub-test-\(UUID().uuidString)")!
        let store = BudgetStore(defaults: d)
        store.setBudget(20, for: "proj-a")
        XCTAssertEqual(store.budget(for: "proj-a"), 20)
        store.setBudget(nil, for: "proj-a")
        XCTAssertNil(store.budget(for: "proj-a"))
    }
    func testFiredThresholdsResetOnMonthChange() {
        let d = UserDefaults(suiteName: "aub-test-\(UUID().uuidString)")!
        let store = BudgetStore(defaults: d)
        store.recordFired(0.8, for: "p", monthKey: "2026-07")
        XCTAssertEqual(store.firedThresholds(for: "p", monthKey: "2026-07"), [0.8])
        XCTAssertEqual(store.firedThresholds(for: "p", monthKey: "2026-08"), [])   // new month clean
    }
}
