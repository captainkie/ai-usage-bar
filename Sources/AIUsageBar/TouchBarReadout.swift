import SwiftUI

/// The full-width readout shown when you tap the Control Strip item — it takes
/// over the whole Touch Bar (system-modal). Touch Bar is always dark.
struct TouchBarReadout: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(red: 0.85, green: 0.55, blue: 0.35))
                    .frame(width: 6, height: 6)
                Text("Claude")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if settings.showFiveHour { gauge("5h", viewModel.sessionWindow) }
            if settings.showWeekly { gauge("wk", viewModel.weeklyWindow) }

            if settings.showModel, let model = viewModel.modelName {
                Text(viewModel.currentEffort.map { "\(model) · \($0)" } ?? model)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .fixedSize()
    }

    private func gauge(_ label: String, _ window: UsageWindow?) -> some View {
        let percent = window?.utilization ?? 0
        return HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 64, height: 6)
                Capsule()
                    .fill(severityColor(percent))
                    .frame(width: max(4, 64 * min(1, percent / 100)), height: 6)
            }

            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)

            if settings.showResetCountdown, let reset = parseISODate(window?.resetsAt) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(formatCountdown(to: reset, now: context.date))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}
