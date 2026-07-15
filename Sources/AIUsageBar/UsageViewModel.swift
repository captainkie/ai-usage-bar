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
    /// The model you're actually using (from the local transcript, not the API).
    @Published private(set) var currentModel: String?
    /// The current reasoning-effort level (from Claude Code settings).
    @Published private(set) var currentEffort: String?
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
            let local = await Task.detached(priority: .utility, operation: {
                (currentModelDisplay(), currentEffortDisplay())
            }).value
            if let model = local.0 { currentModel = model }
            currentEffort = local.1
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

    /// The model you're actually running (see `currentModel`).
    var modelName: String? { currentModel }

    var sessionPercent: Int { Int((sessionWindow?.utilization ?? 0).rounded()) }
    var weeklyPercent: Int { Int((weeklyWindow?.utilization ?? 0).rounded()) }

    /// Populates the view model with representative data for generating the
    /// README screenshots (see AIUSAGEBAR_SHOTS in main.swift).
    func injectMockForScreenshots() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let ahead: (Double) -> String = { iso.string(from: Date().addingTimeInterval($0)) }

        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 37, resetsAt: ahead(3 * 3600 + 12 * 60)),
            sevenDay: UsageWindow(utilization: 49, resetsAt: ahead(24 * 3600 + 7 * 3600)),
            limits: nil
        )
        plan = "Max"
        currentModel = "Opus 4.8"
        currentEffort = "xHigh"
        lastUpdated = Date()
        isStale = false
        phase = .loaded(usage)
    }
}
