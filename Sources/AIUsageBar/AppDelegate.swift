import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let viewModel = UsageViewModel()
    private let touchBar = TouchBarController()
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

        touchBar.onTapFallback = { [weak self] in self?.togglePopover() }
        touchBar.install(viewModel: viewModel)

        updateDisplays()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.remove()
    }

    // MARK: - Data

    private func refresh() {
        Task { @MainActor in
            await viewModel.reload()
            updateDisplays()
        }
    }

    // MARK: - Menu bar + Touch Bar title

    private func updateDisplays() {
        let title = compactTitle()
        if let button = statusItem.button {
            button.image = nil
            button.attributedTitle = title
        }
        touchBar.update(title)
    }

    /// Shared compact rendering used by both the menu bar and the Touch Bar.
    private func compactTitle() -> NSAttributedString {
        switch viewModel.phase {
        case .loading:
            return plain("AI …", color: .secondaryLabelColor)

        case .failed(let kind, _):
            switch kind {
            case .auth:
                return plain("⚠ login required", color: .systemOrange)
            case .transient:
                return plain("AI …", color: .secondaryLabelColor)
            }

        case .loaded:
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
            return text
        }
    }

    private func plain(_ string: String, color: NSColor) -> NSAttributedString {
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
            // Bring the app forward so the popover can key even when triggered
            // from the Touch Bar while another app is focused.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
