import Foundation

/// One usage window normalized across providers.
struct UsageGauge: Identifiable {
    let label: String       // "5h", "wk", "mo"
    let percent: Double
    let resetAt: Date?
    var id: String { label }
}

/// A provider's usage, rendered as a card in the panel.
struct ProviderCard: Identifiable {
    let provider: Provider
    var gauges: [UsageGauge] = []
    var note: String? = nil     // plan / tier (e.g. "Free", "Unlimited")
    var error: String? = nil    // set when signed out / fetch failed
    var id: String { provider.id }
}

/// "18000s" -> "5h", "604800s" -> "wk", "2592000s" -> "mo".
func windowLabel(_ seconds: Double?) -> String {
    guard let s = seconds, s > 0 else { return "usage" }
    switch Int(s) {
    case 18000:   return "5h"
    case 604_800: return "wk"
    case 2_592_000: return "mo"
    default:
        if s >= 86_400 { return "\(Int(s / 86_400))d" }
        return "\(Int(s / 3_600))h"
    }
}
