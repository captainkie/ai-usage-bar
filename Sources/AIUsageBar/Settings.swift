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
    }
}
