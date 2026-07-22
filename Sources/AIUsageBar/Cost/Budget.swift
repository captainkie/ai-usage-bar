import Foundation

struct BudgetStatus {
    let spent: Double
    let limit: Double
    var fraction: Double { limit > 0 ? spent / limit : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
    enum Level { case normal, warn, over }
    var level: Level { fraction >= 1 ? .over : (fraction >= 0.8 ? .warn : .normal) }
}

enum Budget {
    static let thresholds: [Double] = [0.8, 1.0]

    /// Thresholds newly crossed given current fraction and those already fired this month.
    static func newlyCrossed(fraction: Double, alreadyFired: Set<Double>) -> [Double] {
        thresholds.filter { fraction >= $0 && !alreadyFired.contains($0) }.sorted()
    }

    /// Calendar-month spend for one project.
    static func monthSpend(events: [UsageEvent], pricing: Pricing = .shared,
                           project: String, now: Date = Date(), cal: Calendar = .current) -> Double {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return 0 }
        var ignore = Set<String>()
        return events.filter { $0.project == project && $0.timestamp >= start }
                     .reduce(0) { $0 + pricing.cost(for: $1, unpriced: &ignore) }
    }

    /// A stable "2026-07" key for month-scoped alert state.
    static func monthKey(_ now: Date = Date(), cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
