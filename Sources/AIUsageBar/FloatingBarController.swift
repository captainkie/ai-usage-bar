import AppKit
import SwiftUI

/// Manages the always-on-top, draggable floating pill.
@MainActor
final class FloatingBarController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var viewModel: UsageViewModel?
    private let positionKey = "floatingBarOrigin"

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

        let hosting = NSHostingView(rootView: FloatingBarView(viewModel: viewModel))
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

        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - 120))
        }

        self.panel = panel
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: positionKey)
    }
}
