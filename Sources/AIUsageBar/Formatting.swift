import SwiftUI

/// Parses ISO-8601 timestamps like "2026-07-15T07:39:59.822518+00:00".
/// `ISO8601DateFormatter` chokes on microsecond precision, so we drop the
/// fractional part before parsing.
func parseISODate(_ string: String?) -> Date? {
    guard var s = string else { return nil }

    if let dot = s.firstIndex(of: ".") {
        var end = s.index(after: dot)
        while end < s.endIndex, s[end].isNumber {
            end = s.index(after: end)
        }
        s.removeSubrange(dot..<end)
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: s)
}

/// "1h 14m", "6d 15h", "0m" — compact reset countdown.
func formatCountdown(to date: Date, now: Date = Date()) -> String {
    let total = max(0, Int(date.timeIntervalSince(now)))
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60

    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

/// Traffic-light colour for a utilization percentage.
func severityColor(_ percent: Double) -> Color {
    switch percent {
    case ..<50: return Color(red: 0.30, green: 0.80, blue: 0.55)   // green
    case ..<80: return Color(red: 0.98, green: 0.72, blue: 0.30)   // amber
    default:    return Color(red: 0.96, green: 0.42, blue: 0.42)   // red
    }
}

import AppKit

func severityNSColor(_ percent: Double) -> NSColor {
    switch percent {
    case ..<50: return NSColor(red: 0.30, green: 0.80, blue: 0.55, alpha: 1)
    case ..<80: return NSColor(red: 0.98, green: 0.72, blue: 0.30, alpha: 1)
    default:    return NSColor(red: 0.96, green: 0.42, blue: 0.42, alpha: 1)
    }
}
