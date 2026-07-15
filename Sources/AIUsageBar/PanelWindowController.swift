import AppKit
import SwiftUI

/// Presents the panel as a custom dropdown window instead of `NSPopover`.
///
/// Why: `NSPopover` mis-positions / flips above the menu bar on multi-monitor
/// setups where another display sits above the menu-bar display. A window we
/// position ourselves is pinned just below the status item and always drops
/// downward, so it never overflows the top of the screen.
@MainActor
final class PanelWindowController: NSObject {
    private var panel: NSPanel?
    private let hosting: NSHostingController<PanelView>
    private var clickMonitor: Any?

    init(rootView: PanelView) {
        hosting = NSHostingController(rootView: rootView)
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(from button: NSStatusBarButton?) {
        if isVisible { close() } else if let button { open(from: button) }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        panel?.orderOut(nil)
    }

    private func open(from button: NSStatusBarButton) {
        let panel = ensurePanel()

        // Size to the SwiftUI content, capped to the screen height.
        hosting.view.layoutSubtreeIfNeeded()
        var size = hosting.view.fittingSize

        guard let buttonWindow = button.window else { return }
        let rectOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        size.height = min(size.height, visible.height - 16)
        panel.setContentSize(size)

        // Right-align to the status item, pinned just below the menu bar,
        // clamped inside the screen.
        var x = rectOnScreen.maxX - size.width
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
        var y = rectOnScreen.minY - size.height - 4
        y = max(visible.minY + 8, y)
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        if let content = panel.contentView {
            content.wantsLayer = true
            content.layer?.cornerRadius = 14
            content.layer?.masksToBounds = true
        }
        self.panel = panel
        return panel
    }
}
