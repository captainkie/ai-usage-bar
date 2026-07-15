import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    enum Phase {
        case loading
        case loaded(UsageResponse)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var plan: String?
    @Published private(set) var tier: String?

    private let service = UsageService()

    func reload() async {
        do {
            // The Keychain read can block on an OS access prompt — keep it off
            // the main actor so the menu bar / popover stay responsive.
            let credentials = try await Task.detached(priority: .utility) {
                try readClaudeCredentials()
            }.value
            let usage = try await service.fetchUsage(token: credentials.accessToken)
            plan = credentials.subscriptionType
            tier = credentials.rateLimitTier
            phase = .loaded(usage)
            lastUpdated = Date()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Derived values for the views

    var sessionWindow: UsageWindow? {
        if case let .loaded(usage) = phase { return usage.fiveHour }
        return nil
    }

    var weeklyWindow: UsageWindow? {
        if case let .loaded(usage) = phase { return usage.sevenDay }
        return nil
    }

    /// The most specific model name the endpoint reports (from a scoped limit).
    var modelName: String? {
        guard case let .loaded(usage) = phase else { return nil }
        return usage.limits?
            .compactMap { $0.scope?.model?.displayName }
            .first
    }

    var sessionPercent: Int { Int((sessionWindow?.utilization ?? 0).rounded()) }
    var weeklyPercent: Int { Int((weeklyWindow?.utilization ?? 0).rounded()) }
}
