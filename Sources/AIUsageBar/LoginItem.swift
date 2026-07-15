import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for launch-at-login.
/// Only works when running as a bundled `.app` (build with scripts/build-app.sh).
enum LoginItem {
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Silently reports failures (e.g. running
    /// unbundled via `swift run`, where registration is not permitted).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("AIUsageBar: launch-at-login toggle failed — \(error.localizedDescription)")
            return false
        }
    }
}
