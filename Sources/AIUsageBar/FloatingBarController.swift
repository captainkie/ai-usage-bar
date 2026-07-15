import AppKit
import SwiftUI

/// Manages the always-on-top, draggable floating pill.
@MainActor
final class FloatingBarController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var viewModel: UsageViewModel?
    private let positionKey = "floatingBarOrigin"

    var onOpenPanel: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    func setViewModel(_ viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    func setVisible(_ visible: Bool) {
        if visible {
            ensurePanel()?.orderFront(nil)
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel? {
        if let panel { return panel }
        guard let viewModel else { return nil }

        let hosting = NSHostingView(rootView: FloatingBarView(
            viewModel: viewModel,
            onOpenPanel: { [weak self] in self?.onOpenPanel() },
            onOpenSettings: { [weak self] in self?.onOpenSettings() }))
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.delegate = self

        let size = panel.frame.size
        var restored: NSPoint?
        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            let point = NSPointFromString(saved)
            // Only reuse a saved position if it's still on a visible screen
            // (a different monitor arrangement can strand it off-screen).
            if Self.isVisible(NSRect(origin: point, size: size)) { restored = point }
        }
        if let restored {
            panel.setFrameOrigin(restored)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 20))
            UserDefaults.standard.removeObject(forKey: positionKey)
        }

        self.panel = panel
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: positionKey)
    }

    private static func isVisible(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }
}
