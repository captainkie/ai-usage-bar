import SwiftUI

let githubURL = URL(string: "https://github.com/captainkie/ai-usage-bar")!

struct PanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var settings = Settings.shared
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            Divider().opacity(0.5)
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            GaugeMark(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("AI Usage").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless).help("Refresh now")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless).help("Settings")
        }
    }

    private var subtitle: String {
        if let plan = viewModel.plan {
            return plan.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return "Claude Code"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)

        case .failed(let kind, let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: kind == .auth
                        ? "exclamationmark.triangle.fill" : "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.30))
                if kind == .auth {
                    Text("Sign in with Claude Code, then hit refresh.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

        case .loaded:
            providerCard
        }
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Circle()
                    .fill(Color(red: 0.85, green: 0.55, blue: 0.35))
                    .frame(width: 7, height: 7)
                Text("Claude Code").font(.subheadline.weight(.semibold))
                Spacer()
                if settings.showModel, let model = viewModel.modelName {
                    HStack(spacing: 5) {
                        Text(model)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                            .foregroundStyle(.secondary)
                        if let effort = viewModel.currentEffort {
                            Text(effort)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(red: 1.0, green: 0.70, blue: 0.14).opacity(0.18), in: Capsule())
                                .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.10))
                        }
                    }
                }
            }

            if settings.showFiveHour {
                GaugeRow(title: "5-hour", window: viewModel.sessionWindow,
                         showReset: settings.showResetCountdown)
            }
            if settings.showWeekly {
                GaugeRow(title: "Weekly", window: viewModel.weeklyWindow,
                         showReset: settings.showResetCountdown)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Link(destination: githubURL) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)

                Spacer()

                if viewModel.isStale {
                    Label("reconnecting…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.30))
                } else if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            HStack {
                Text("by Fosivo Labs").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.borderless).foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}

/// One labelled progress bar with an optional live reset countdown.
struct GaugeRow: View {
    let title: String
    let window: UsageWindow?
    var showReset: Bool = true

    var body: some View {
        let percent = window?.utilization ?? 0
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(severityColor(percent))
            }

            ProgressBar(fraction: percent / 100, color: severityColor(percent))

            if showReset, let reset = parseISODate(window?.resetsAt) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label("resets in \(formatCountdown(to: reset, now: context.date))",
                          systemImage: "clock")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.85), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(7, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 9)
    }
}
