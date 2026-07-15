import AppKit
import SwiftUI

/// Renders README images from the real SwiftUI components (no screen-recording
/// permission needed). Triggered by AIUSAGEBAR_SHOTS=<dir> in main.swift.
///
/// Uses a static card (not the live PanelView) because ImageRenderer can't
/// rasterize interactive Buttons — it draws them as placeholder glyphs.
@MainActor
func renderShots(to dir: String) {
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: .darkAqua)

    let vm = UsageViewModel()
    vm.injectMockForScreenshots()

    func save<V: View>(_ view: V, _ name: String) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("render failed: \(name)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        print("wrote \(name)")
    }

    save(HeroShot(viewModel: vm), "panel.png")
    save(TouchBarShot(viewModel: vm), "touchbar.png")
    save(FloatingBarShot(viewModel: vm), "floatingbar.png")
}

private let amber = Color(red: 1.0, green: 0.70, blue: 0.14)

private struct HeroShot: View {
    let viewModel: UsageViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.17, green: 0.13, blue: 0.25),
                         Color(red: 0.07, green: 0.10, blue: 0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 0) {
                menuBar
                Spacer().frame(height: 22)
                HStack {
                    Spacer()
                    ShotCard(vm: viewModel)
                        .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
                        .padding(.trailing, 34)
                }
                Spacer(minLength: 24)
            }
        }
        .frame(width: 760, height: 660)
    }

    private var menuBar: some View {
        HStack(spacing: 16) {
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(severityColor(37)).frame(width: 7, height: 7)
                Text("5h 37%  wk 49%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            Image(systemName: "wifi")
            Image(systemName: "battery.75")
            Text("16:26").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(.black.opacity(0.35))
    }
}

/// A static mirror of PanelView for rendering (no interactive Buttons).
private struct ShotCard: View {
    let vm: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                GaugeMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Usage").font(.headline).foregroundStyle(.white)
                    Text(vm.plan ?? "Claude Code").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                Image(systemName: "gearshape")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Circle().fill(Color(red: 0.85, green: 0.55, blue: 0.35)).frame(width: 7, height: 7)
                    Text("Claude Code").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 5) {
                        Text(vm.modelName ?? "Opus 4.8")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.10), in: Capsule())
                            .foregroundStyle(.white.opacity(0.75))
                        if let effort = vm.currentEffort {
                            Text(effort)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(amber.opacity(0.20), in: Capsule())
                                .foregroundStyle(amber)
                        }
                    }
                }
                GaugeRow(title: "5-hour", window: vm.sessionWindow, showReset: true)
                GaugeRow(title: "Weekly", window: vm.weeklyWindow, showReset: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07)))
            )

            ForEach(vm.extraCards) { ProviderCardView(card: $0) }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("GitHub")
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("Updated 16:26").font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
                HStack {
                    Text("by Fosivo Labs").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("Quit").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.13))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08)))
        )
    }
}

private struct TouchBarShot: View {
    let viewModel: UsageViewModel

    var body: some View {
        ZStack {
            Color.black
            HStack {
                TouchBarReadout(viewModel: viewModel)
                Spacer()
            }
            .padding(.leading, 24)
        }
        .frame(width: 1000, height: 44)
    }
}

private struct FloatingBarShot: View {
    let viewModel: UsageViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.16, blue: 0.22),
                         Color(red: 0.06, green: 0.08, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            pill.shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        }
        .frame(width: 720, height: 200)
    }

    private var pill: some View {
        HStack(spacing: 12) {
            GaugeMark(size: 18)
            segment("5h", viewModel.sessionWindow)
            segment("wk", viewModel.weeklyWindow)
            Text("\(viewModel.modelName ?? "Opus 4.8")\(viewModel.currentEffort.map { " · \($0)" } ?? "")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        )
    }

    private func segment(_ label: String, _ window: UsageWindow?) -> some View {
        let percent = window?.utilization ?? 0
        return HStack(spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(width: 46, height: 5)
                Capsule().fill(severityColor(percent))
                    .frame(width: max(4, 46 * min(1, percent / 100)), height: 5)
            }
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(severityColor(percent))
        }
    }
}
