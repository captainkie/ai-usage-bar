import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    enum FailKind {
        case auth        // real login problem — user must sign in to Claude Code
        case transient   // 429 / network / decode — keep showing cached data
    }

    enum Phase {
        case loading
        case loaded(UsageResponse)
        case failed(FailKind, String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var plan: String?
    @Published private(set) var tier: String?
    /// True when the latest refresh failed but we are still showing cached data.
    @Published private(set) var isStale = false

    private var lastGood: UsageResponse?
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
            lastGood = usage
            lastUpdated = Date()
            isStale = false
            phase = .loaded(usage)
        } catch {
            let kind = Self.classify(error)
            if kind == .transient, let cached = lastGood {
                // Don't scare the user with "login required" over a blip —
                // keep the last good numbers and just mark them stale.
                isStale = true
                phase = .loaded(cached)
            } else {
                phase = .failed(kind, Self.message(for: error, kind: kind))
            }
        }
    }

    private static func classify(_ error: Error) -> FailKind {
        if let e = error as? UsageServiceError, case .unauthorized = e { return .auth }
        if error is KeychainError { return .auth }
        return .transient
    }

    private static func message(for error: Error, kind: FailKind) -> String {
        switch kind {
        case .auth:
            return error.localizedDescription
        case .transient:
            return "Can’t reach Anthropic — retrying…"
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
