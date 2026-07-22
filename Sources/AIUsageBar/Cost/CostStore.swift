import Foundation
import Combine
#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

/// Orchestrates the cost engine for the UI: scans local session files off the
/// main thread, exposes the current window summary, and fires budget alerts.
@MainActor
final class CostStore: ObservableObject {
    @Published var window: Window = .days7 { didSet { recompute() } }
    @Published var filterProject: String? { didSet { recompute() } }
    @Published private(set) var summary = WindowSummary()
    @Published private(set) var loading = false

    private var events: [UsageEvent] = []
    private let cache = CostCache()
    private let budgets = BudgetStore()
    private let settings = Settings.shared
    private var lastBudgetCheck = Date.distantPast

    /// Full scan on a background task, then recompute + budget check.
    func refresh() {
        loading = true
        Task.detached(priority: .utility) {
            let events = SessionParser.scanAll()
            await MainActor.run {
                self.events = events
                self.loading = false
                self.recompute()
                self.checkBudgets()
            }
        }
    }

    /// Background budget check (called on the app's refresh cadence even when the
    /// cost window is closed). Scanning is expensive, so skip it entirely unless
    /// alerts are on AND at least one budget is set, and throttle to ~10 minutes.
    func backgroundBudgetCheck() {
        guard settings.budgetAlerts, !budgets.allBudgets().isEmpty,
              Date().timeIntervalSince(lastBudgetCheck) > 600 else { return }
        lastBudgetCheck = Date()
        Task.detached(priority: .utility) {
            let events = SessionParser.scanAll()
            await MainActor.run { self.events = events; self.checkBudgets() }
        }
    }

    func budget(for project: String) -> Double? { budgets.budget(for: project) }
    func setBudget(_ v: Double?, for project: String) { budgets.setBudget(v, for: project); recompute() }
    func monthStatus(for project: String) -> BudgetStatus? {
        guard let limit = budgets.budget(for: project) else { return nil }
        return BudgetStatus(spent: Budget.monthSpend(events: events, project: project), limit: limit)
    }
    func openInBrowser() {
        DashboardExporter.writeAndOpen(events: events, budgets: budgets.allBudgets())
    }

    private func recompute() {
        summary = CostAggregator.summary(events: events, window: window, project: filterProject)
    }

    private func checkBudgets() {
        guard settings.budgetAlerts else { return }
        let monthKey = Budget.monthKey()
        for (project, limit) in budgets.allBudgets() {
            let spent = Budget.monthSpend(events: events, project: project)
            let fraction = limit > 0 ? spent / limit : 0
            let fired = budgets.firedThresholds(for: project, monthKey: monthKey)
            for t in Budget.newlyCrossed(fraction: fraction, alreadyFired: fired) {
                budgets.recordFired(t, for: project, monthKey: monthKey)
                notify(project: project, threshold: t, spent: spent, limit: limit)
            }
        }
    }

    private func notify(project: String, threshold: Double, spent: Double, limit: Double) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = threshold >= 1 ? "Budget exceeded" : "Budget at \(Int(threshold * 100))%"
            c.body = "\(projectLabel(project)) — $\(String(format: "%.2f", spent)) of $\(String(format: "%.0f", limit)) this month."
            center.add(UNNotificationRequest(identifier: "\(project)-\(threshold)", content: c, trigger: nil))
        }
        #endif
    }
}
