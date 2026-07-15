import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var scans = ProviderScanner.scan()
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2.weight(.bold))

                section("Providers") {
                    ForEach(scans) { ProviderRow(scan: $0, settings: settings) }
                }

                section("Show in the panel") {
                    toggle("5-hour limit", $settings.showFiveHour)
                    toggle("Weekly limit", $settings.showWeekly)
                    toggle("Current model", $settings.showModel)
                    toggle("Reset countdown", $settings.showResetCountdown)
                }

                section("General") {
                    HStack {
                        Text("Refresh every")
                        Spacer()
                        Stepper("\(settings.refreshSeconds)s",
                                value: $settings.refreshSeconds,
                                in: Settings.minRefresh...600, step: 15)
                            .fixedSize()
                    }
                    .padding(.vertical, 2)

                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .disabled(!LoginItem.isBundledApp)
                        .onChange(of: launchAtLogin) { newValue in
                            if !LoginItem.setEnabled(newValue) { launchAtLogin = LoginItem.isEnabled }
                        }
                }
            }
            .padding(20)
        }
        .frame(width: 420, height: 540)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}
