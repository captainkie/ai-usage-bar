import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let viewModel = UsageViewModel()
    private var refreshTimer: Timer?

    private let refreshInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PanelView(
                viewModel: viewModel,
                onRefresh: { [weak self] in self?.refresh() },
                onQuit: { NSApp.terminate(nil) }
            )
        )

        updateButton()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Data

    private func refresh() {
        Task { @MainActor in
            await viewModel.reload()
            updateButton()
        }
    }

    // MARK: - Menu bar title

    private func updateButton() {
        guard let button = statusItem.button else { return }

        switch viewModel.phase {
        case .loading:
            button.attributedTitle = title("Loading…", color: .secondaryLabelColor)

        case .failed:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                   accessibilityDescription: "Login required")
            button.attributedTitle = title("", color: .systemOrange)

        case .loaded:
            button.image = nil
            let session = viewModel.sessionPercent
            let weekly = viewModel.weeklyPercent

            let text = NSMutableAttributedString()
            text.append(NSAttributedString(
                string: "● ",
                attributes: [
                    .foregroundColor: severityNSColor(Double(session)),
                    .font: NSFont.systemFont(ofSize: 10),
                ]
            ))
            text.append(NSAttributedString(
                string: "5h \(session)%  7d \(weekly)%",
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                ]
            ))
            button.attributedTitle = text
        }
    }

    private func title(_ string: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            ]
        )
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
