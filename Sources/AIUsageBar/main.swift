import AppKit

// Headless self-test: exercises the full non-UI stack (Keychain -> API ->
// decode -> formatting) and prints the result. Run with AIUSAGEBAR_PRINT=1.
if ProcessInfo.processInfo.environment["AIUSAGEBAR_PRINT"] == "1" {
    runSelfTest()
    exit(0)
}

// Menu-bar-only app: no Dock icon, no main window.
// Program start is already on the main thread, so asserting main-actor
// isolation here is safe and lets us touch the @MainActor UI types.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

func runSelfTest() {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            print("touchbar: supported=\(TouchBarController.isSupported)")
            // Debug override: skip the Keychain gate when a token is injected.
            let injected = ProcessInfo.processInfo.environment["AIUSAGEBAR_TOKEN"]
            let credentials: ClaudeCredentials
            if let injected, !injected.isEmpty {
                credentials = ClaudeCredentials(accessToken: injected, refreshToken: nil,
                                                expiresAt: nil, subscriptionType: "(injected)",
                                                rateLimitTier: "(injected)")
            } else {
                credentials = try readClaudeCredentials()
            }
            let usage = try await UsageService().fetchUsage(token: credentials.accessToken)

            let session = Int((usage.fiveHour?.utilization ?? 0).rounded())
            let weekly = Int((usage.sevenDay?.utilization ?? 0).rounded())
            let model = usage.limits?.compactMap { $0.scope?.model?.displayName }.first ?? "-"

            print("plan   : \(credentials.subscriptionType ?? "-")  tier: \(credentials.rateLimitTier ?? "-")")
            print("menubar: ● 5h \(session)%  7d \(weekly)%")
            print("model  : \(model)")
            if let reset = parseISODate(usage.fiveHour?.resetsAt) {
                print("5-hour : \(session)%  resets in \(formatCountdown(to: reset))")
            }
            if let reset = parseISODate(usage.sevenDay?.resetsAt) {
                print("weekly : \(weekly)%  resets in \(formatCountdown(to: reset))")
            }
            print("SELFTEST OK")
        } catch {
            print("SELFTEST ERROR: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
}
