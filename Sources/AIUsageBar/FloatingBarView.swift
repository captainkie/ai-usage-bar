import SwiftUI

/// A compact draggable pill that floats above every window.
struct FloatingBarView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            GaugeMark(size: 18)

            switch viewModel.phase {
            case .loading:
                Text("AI …").font(.system(size: 11)).foregroundStyle(.secondary)
            case .failed(let kind, _):
                Text(kind == .auth ? "login required" : "…")
                    .font(.system(size: 11))
                    .foregroundStyle(kind == .auth ? Color(red: 0.98, green: 0.72, blue: 0.30) : .secondary)
            case .loaded:
                if settings.showFiveHour { segment("5h", viewModel.sessionWindow) }
                if settings.showWeekly { segment("wk", viewModel.weeklyWindow) }
                if settings.showModel, let model = viewModel.modelName {
                    Text(viewModel.currentEffort.map { "\(model) · \($0)" } ?? model)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }

    private func segment(_ label: String, _ window: UsageWindow?) -> some View {
        let percent = window?.utilization ?? 0
        return HStack(spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 42, height: 5)
                Capsule().fill(severityColor(percent))
                    .frame(width: max(4, 42 * min(1, percent / 100)), height: 5)
            }
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(severityColor(percent))
        }
    }
}
