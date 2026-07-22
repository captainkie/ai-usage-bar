import SwiftUI
import Charts

struct CostView: View {
    @StateObject private var store = CostStore()
    @State private var showBudgets = false
    @State private var showModels = true

    private var accent: Color { Color(red: 0.85, green: 0.55, blue: 0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $store.window) {
                ForEach(Window.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()

            hero
            if !store.summary.days.isEmpty { chart }
            projects
            if showModels && !store.summary.byModel.isEmpty { models }
            footer
        }
        .padding(18)
        .frame(width: 460)
        .onAppear { store.refresh() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = store.filterProject {
                HStack(spacing: 6) {
                    Text(projectLabel(p)).font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Button { store.filterProject = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            Text(money(store.summary.totalCost)).font(.system(size: 40, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
            Text("in \(tokens(store.summary.input)) / out \(tokens(store.summary.output)) · \(store.summary.sessions) sessions")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart(store.summary.days) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Cost", d.cost))
                .foregroundStyle(accent.opacity(0.85))
        }
        .frame(height: 90).chartYAxis(.hidden)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BY PROJECT").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            ForEach(store.summary.byProject) { p in
                Button { store.filterProject = (store.filterProject == p.project ? nil : p.project) } label: {
                    VStack(spacing: 5) {
                        HStack {
                            Text(projectLabel(p.project)).font(.subheadline)
                            Spacer()
                            Text(money(p.cost)).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        if let st = store.monthStatus(for: p.project) {
                            HStack(spacing: 8) {
                                ProgressBar(fraction: min(1, st.fraction), color: budgetColor(st.level))
                                Text("\(money(st.spent)) / \(money(st.limit)) · \(st.percent)%")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .background(store.filterProject == p.project ? accent.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BY MODEL").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            ForEach(store.summary.byModel.prefix(5).map { $0 }) { m in
                HStack {
                    Text(prettyModelName(m.model)).font(.subheadline)
                    Spacer()
                    Text(money(m.cost)).font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open in browser") { store.openInBrowser() }
            Spacer()
            Button("Edit budgets") { showBudgets = true }
        }
        .font(.caption)
        .sheet(isPresented: $showBudgets) { BudgetSettingsView(store: store) }
    }

    private func budgetColor(_ l: BudgetStatus.Level) -> Color {
        switch l { case .normal: return severityColor(20); case .warn: return severityColor(85); case .over: return severityColor(120) }
    }
    private func money(_ v: Double) -> String { "$" + String(format: "%.2f", v) }
    private func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n)/1e6) : n >= 1000 ? "\(n/1000)K" : "\(n)"
    }
}
