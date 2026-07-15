import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let viewModel = UsageViewModel()
    private let touchBar = TouchBarController()
    private let floatingBar = FloatingBarController()
    private let settings = Settings.shared

    private var tickTimer: Timer?
    private var lastRefresh = Date.distantPast
    private var settingsObserver: AnyCancellable?

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

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
                onOpenSettings: { [weak self] in self?.showSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        )

        touchBar.onTapFallback = { [weak self] in self?.togglePopover() }
        touchBar.install(viewModel: viewModel)

        floatingBar.setViewModel(viewModel)
        floatingBar.setVisible(settings.showFloatingBar)

        // Re-render the menu bar when display settings change.
        settingsObserver = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateDisplays() }
        }

        updateDisplays()
        refresh()

        // Fixed small tick; refresh once the chosen interval has elapsed so
        // changing the interval takes effect without rescheduling.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        if !settings.hasOnboarded { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.remove()
    }

    // MARK: - Data

    private func tick() {
        let interval = Double(max(Settings.minRefresh, settings.refreshSeconds))
        if Date().timeIntervalSince(lastRefresh) >= interval { refresh() }
    }

    private func refresh() {
        lastRefresh = Date()
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
        floatingBar.setVisible(settings.showFloatingBar)
    }

    private func compactTitle() -> NSAttributedString {
        switch viewModel.phase {
        case .loading:
            return plain("AI …", color: .secondaryLabelColor)

        case .failed(let kind, _):
            switch kind {
            case .auth:      return plain("⚠ login required", color: .systemOrange)
            case .transient: return plain("AI …", color: .secondaryLabelColor)
            }

        case .loaded:
            var segments: [String] = []
            if settings.showFiveHour { segments.append("5h \(viewModel.sessionPercent)%") }
            if settings.showWeekly { segments.append("wk \(viewModel.weeklyPercent)%") }
            if segments.isEmpty { segments.append("5h \(viewModel.sessionPercent)%") }

            let text = NSMutableAttributedString()
            text.append(NSAttributedString(
                string: "● ",
                attributes: [
                    .foregroundColor: severityNSColor(Double(viewModel.sessionPercent)),
                    .font: NSFont.systemFont(ofSize: 10),
                ]
            ))
            text.append(NSAttributedString(
                string: segments.joined(separator: "  "),
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
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Windows

    private func makeWindow<V: View>(title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(
                title: "Welcome",
                size: NSSize(width: 440, height: 480),
                view: OnboardingView(onDone: { [weak self] in
                    self?.onboardingWindow?.close()
                    self?.refresh()
                })
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "AI Usage Settings",
                size: NSSize(width: 420, height: 540),
                view: SettingsView()
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
