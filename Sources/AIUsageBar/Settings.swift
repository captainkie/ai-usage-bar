import SwiftUI

/// User preferences, persisted to `UserDefaults`. Never holds any token.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let store = UserDefaults.standard

    @Published var enabledProviders: Set<Provider> { didSet { save() } }
    @Published var showFiveHour: Bool { didSet { save() } }
    @Published var showWeekly: Bool { didSet { save() } }
    @Published var showModel: Bool { didSet { save() } }
    @Published var showResetCountdown: Bool { didSet { save() } }
    @Published var refreshSeconds: Int { didSet { save() } }
    @Published var showFloatingBar: Bool { didSet { save() } }
    @Published var hasOnboarded: Bool { didSet { save() } }
    @Published var budgetAlerts: Bool { didSet { save() } }

    /// Minimum poll interval — be a good citizen of an undocumented endpoint.
    static let minRefresh = 30

    private init() {
        let raw = store.stringArray(forKey: Key.providers) ?? [Provider.claude.rawValue]
        enabledProviders = Set(raw.compactMap(Provider.init(rawValue:)))
        showFiveHour       = store.object(forKey: Key.fiveHour) as? Bool ?? true
        showWeekly         = store.object(forKey: Key.weekly) as? Bool ?? true
        showModel          = store.object(forKey: Key.model) as? Bool ?? true
        showResetCountdown = store.object(forKey: Key.reset) as? Bool ?? true
        refreshSeconds     = store.object(forKey: Key.refresh) as? Int ?? 180
        showFloatingBar    = store.object(forKey: Key.floating) as? Bool ?? false
        hasOnboarded       = store.bool(forKey: Key.onboarded)
        budgetAlerts       = store.object(forKey: Key.budgetAlerts) as? Bool ?? true
    }

    func isEnabled(_ provider: Provider) -> Bool { enabledProviders.contains(provider) }

    func setEnabled(_ provider: Provider, _ on: Bool) {
        if on { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
    }

    private func save() {
        store.set(enabledProviders.map(\.rawValue), forKey: Key.providers)
        store.set(showFiveHour, forKey: Key.fiveHour)
        store.set(showWeekly, forKey: Key.weekly)
        store.set(showModel, forKey: Key.model)
        store.set(showResetCountdown, forKey: Key.reset)
        store.set(max(Self.minRefresh, refreshSeconds), forKey: Key.refresh)
        store.set(showFloatingBar, forKey: Key.floating)
        store.set(hasOnboarded, forKey: Key.onboarded)
        store.set(budgetAlerts, forKey: Key.budgetAlerts)
    }

    private enum Key {
        static let providers = "enabledProviders"
        static let fiveHour = "showFiveHour"
        static let weekly = "showWeekly"
        static let model = "showModel"
        static let reset = "showResetCountdown"
        static let refresh = "refreshSeconds"
        static let floating = "showFloatingBar"
        static let onboarded = "hasOnboarded"
        static let budgetAlerts = "budgetAlerts"
    }
}

/// Persists per-project monthly budgets + fired-alert state. Injectable defaults for tests.
final class BudgetStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private let budgetsKey = "projectBudgets"          // [project: Double]
    private let firedKey = "budgetFired"               // [monthKey: [project: [Double]]]

    func allBudgets() -> [String: Double] {
        defaults.dictionary(forKey: budgetsKey) as? [String: Double] ?? [:]
    }
    func budget(for project: String) -> Double? { allBudgets()[project] }
    func setBudget(_ value: Double?, for project: String) {
        var m = allBudgets()
        if let value, value > 0 { m[project] = value } else { m.removeValue(forKey: project) }
        defaults.set(m, forKey: budgetsKey)
    }

    private func firedRoot() -> [String: [String: [Double]]] {
        defaults.dictionary(forKey: firedKey) as? [String: [String: [Double]]] ?? [:]
    }
    func firedThresholds(for project: String, monthKey: String) -> Set<Double> {
        Set(firedRoot()[monthKey]?[project] ?? [])
    }
    func recordFired(_ threshold: Double, for project: String, monthKey: String) {
        var root = firedRoot()
        // prune other months so state stays small and resets automatically
        root = root.filter { $0.key == monthKey }
        var month = root[monthKey] ?? [:]
        var list = Set(month[project] ?? []); list.insert(threshold)
        month[project] = Array(list); root[monthKey] = month
        defaults.set(root, forKey: firedKey)
    }
}
