import SwiftUI

struct BudgetSettingsView: View {
    @ObservedObject var store: CostStore
    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monthly budgets").font(.headline)
            Toggle("Notify me at 80% and 100%", isOn: $settings.budgetAlerts)
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.summary.byProject) { p in
                        HStack {
                            Text(projectLabel(p.project)).font(.subheadline)
                            Spacer()
                            TextField("no budget", value: Binding(
                                get: { store.budget(for: p.project) ?? 0 },
                                set: { store.setBudget($0 > 0 ? $0 : nil, for: p.project) }
                            ), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                            Text("/ mo").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(18).frame(width: 380, height: 420)
    }
}
