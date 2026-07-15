import AppKit

// MARK: - DFRFoundation private bridge
//
// The Touch Bar Control Strip (the always-visible right side) is driven by the
// private DFRFoundation framework + private `+[NSTouchBarItem addSystemTrayItem:]`.
// These are undocumented but stable and used by every Touch Bar utility
// (Pock, MTMR, …). Not App Store safe — fine for a self-hosted open tool.

private typealias DFRSetPresenceFn = @convention(c) (CFString, Bool) -> Void

private let dfrSetControlStripPresence: DFRSetPresenceFn? = {
    let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
    guard let handle = dlopen(path, RTLD_NOW),
          let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
    else { return nil }
    return unsafeBitCast(sym, to: DFRSetPresenceFn.self)
}()

private let controlStripIdentifier = NSTouchBarItem.Identifier("co.th.aiusagebar.controlstrip")

/// Installs a persistent AI-usage item in the Touch Bar Control Strip.
@MainActor
final class TouchBarController: NSObject {
    private var trayItem: NSCustomTouchBarItem?
    private let button = NSButton(title: "AI", target: nil, action: nil)
    var onTap: (() -> Void)?

    /// Whether this machine can host a Control Strip item (i.e. has a Touch Bar).
    nonisolated static var isSupported: Bool {
        dfrSetControlStripPresence != nil && canAddSystemTrayItem
    }

    nonisolated static var canAddSystemTrayItem: Bool {
        (NSTouchBarItem.self as AnyObject).responds(to: NSSelectorFromString("addSystemTrayItem:"))
    }

    func install() {
        guard TouchBarController.isSupported else { return }

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

    @objc private func handleTap() {
        onTap?()
    }
}
