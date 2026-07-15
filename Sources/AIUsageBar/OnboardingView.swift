import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var settings = Settings.shared
    var onDone: () -> Void

    @State private var scans: [ProviderScan] = ProviderScanner.scan()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI tools found on your Mac")
                        .font(.subheadline.weight(.semibold))
                        .padding(.bottom, 2)
                    ForEach(scans) { scan in
                        ProviderRow(scan: scan, settings: settings)
                    }
                    Text("Only Claude Code shows live limits today — the others are ready for when support lands. You can change this anytime in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .padding(18)
            }
            Divider()
            HStack {
                Spacer()
                Button("Get Started") {
                    settings.hasOnboarded = true
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 440, height: 480)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            Text("Welcome to AI Usage")
                .font(.title2.weight(.bold))
            Text("by Fosivo Labs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

/// One row in onboarding / settings: name, status, and an enable toggle.
struct ProviderRow: View {
    let scan: ProviderScan
    @ObservedObject var settings: Settings

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(scan.installed ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(scan.provider.displayName).font(.body.weight(.medium))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if scan.provider.isSupported && scan.installed {
                Toggle("", isOn: Binding(
                    get: { settings.isEnabled(scan.provider) },
                    set: { settings.setEnabled(scan.provider, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            } else if !scan.provider.isSupported {
                Text("Coming soon")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusText: String {
        if !scan.installed { return "Not signed in" }
        return scan.provider.isSupported ? "Signed in" : "Signed in · support coming"
    }
}
