import AppKit
import SwiftUI

// MARK: - DFRFoundation private bridge
//
// The Touch Bar Control Strip (the always-visible right side) is driven by the
// private DFRFoundation framework + private `+[NSTouchBarItem addSystemTrayItem:]`
// and `+[NSTouchBar presentSystemModal…]`. These are undocumented but stable and
// used by every Touch Bar utility (Pock, MTMR, …). Not App Store safe — fine for
// a self-hosted open tool.

private typealias DFRSetPresenceFn = @convention(c) (CFString, Bool) -> Void

private let dfrSetControlStripPresence: DFRSetPresenceFn? = {
    let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
    guard let handle = dlopen(path, RTLD_NOW),
          let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
    else { return nil }
    return unsafeBitCast(sym, to: DFRSetPresenceFn.self)
}()

private let controlStripIdentifier = NSTouchBarItem.Identifier("co.th.aiusagebar.controlstrip")
private let readoutIdentifier = NSTouchBarItem.Identifier("co.th.aiusagebar.readout")
private let closeIdentifier = NSTouchBarItem.Identifier("co.th.aiusagebar.close")

/// Installs a persistent AI-usage item in the Touch Bar Control Strip, and
/// presents a full-width readout when it is tapped.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private var trayItem: NSCustomTouchBarItem?
    private let button = NSButton(title: "AI", target: nil, action: nil)
    private var fullTouchBar: NSTouchBar?
    private weak var viewModel: UsageViewModel?

    /// Fallback if presenting the modal Touch Bar isn't available.
    var onTapFallback: (() -> Void)?

    nonisolated static var isSupported: Bool {
        dfrSetControlStripPresence != nil && canAddSystemTrayItem
    }

    nonisolated static var canAddSystemTrayItem: Bool {
        (NSTouchBarItem.self as AnyObject).responds(to: NSSelectorFromString("addSystemTrayItem:"))
    }

    func install(viewModel: UsageViewModel) {
        guard TouchBarController.isSupported else { return }
        self.viewModel = viewModel

        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(handleTap)
        button.title = "AI …"

        let item = NSCustomTouchBarItem(identifier: controlStripIdentifier)
        item.view = button
        trayItem = item

        let addSel = NSSelectorFromString("addSystemTrayItem:")
        let cls: AnyObject = NSTouchBarItem.self
        if cls.responds(to: addSel) {
            _ = cls.perform(addSel, with: item)
        }
        dfrSetControlStripPresence?(controlStripIdentifier.rawValue as CFString, true)
    }

    /// Update the compact Control Strip label.
    func update(_ attributedTitle: NSAttributedString) {
        button.attributedTitle = attributedTitle
    }

    func remove() {
        dfrSetControlStripPresence?(controlStripIdentifier.rawValue as CFString, false)
        let removeSel = NSSelectorFromString("removeSystemTrayItem:")
        let cls: AnyObject = NSTouchBarItem.self
        if let item = trayItem, cls.responds(to: removeSel) {
            _ = cls.perform(removeSel, with: item)
        }
        trayItem = nil
    }

    // MARK: - Full-width modal readout

    @objc private func handleTap() {
        presentFull()
    }

    private func presentFull() {
        // Make sure the Control Strip item is present before anchoring to it.
        dfrSetControlStripPresence?(controlStripIdentifier.rawValue as CFString, true)

        let bar = fullTouchBar ?? makeFullTouchBar()
        fullTouchBar = bar

        let cls: AnyObject = NSTouchBar.self
        for name in ["presentSystemModalTouchBar:systemTrayItemIdentifier:",
                     "presentSystemModalFunctionBar:systemTrayItemIdentifier:"] {
            let sel = NSSelectorFromString(name)
            if cls.responds(to: sel) {
                _ = cls.perform(sel, with: bar, with: controlStripIdentifier.rawValue as NSString)
                return
            }
        }
        onTapFallback?()   // couldn't present modal — open the popover instead
    }

    /// Collapse the modal back to the Control Strip item (which stays tappable).
    /// NOT `dismiss…`, which tears the item down so it can't be reopened.
    @objc private func minimizeFull() {
        guard let bar = fullTouchBar else { return }
        let cls: AnyObject = NSTouchBar.self
        for name in ["minimizeSystemModalTouchBar:", "minimizeSystemModalFunctionBar:"] {
            let sel = NSSelectorFromString(name)
            if cls.responds(to: sel) {
                _ = cls.perform(sel, with: bar)
                return
            }
        }
    }

    private func makeFullTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [closeIdentifier, readoutIdentifier]
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case readoutIdentifier:
            guard let viewModel else { return nil }
            let item = NSCustomTouchBarItem(identifier: identifier)
            let host = NSHostingView(rootView: TouchBarReadout(viewModel: viewModel))
            host.setFrameSize(host.fittingSize)
            item.view = host
            return item

        case closeIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let close = NSButton(
                image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
                    ?? NSImage(),
                target: self, action: #selector(minimizeFull)
            )
            close.bezelStyle = .rounded
            item.view = close
            return item

        default:
            return nil
        }
    }
}
