import Foundation

/// Fetches Codex (OpenAI/ChatGPT) usage from the same endpoint the Codex CLI
/// uses. Reads the OAuth token from `~/.codex/auth.json` (a local file — no
/// Keychain, no prompt).
struct CodexService {
    func fetch() async -> ProviderCard {
        guard let creds = Self.readCredentials() else {
            return ProviderCard(provider: .codex, error: "Not signed in — run `codex login`")
        }
        do {
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
            request.setValue(creds.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("AIUsageBar/0.2", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderCard(provider: .codex, error: "Codex login expired")
            }
            guard status == 200 else {
                return ProviderCard(provider: .codex, error: "Couldn’t reach Codex")
            }

            let usage = try JSONDecoder().decode(CodexUsage.self, from: data)
            var gauges: [UsageGauge] = []
            if let w = usage.rateLimit?.primaryWindow { gauges.append(w.gauge) }
            if let w = usage.rateLimit?.secondaryWindow { gauges.append(w.gauge) }
            return ProviderCard(provider: .codex, gauges: gauges, note: usage.planType?.capitalized)
        } catch {
            return ProviderCard(provider: .codex, error: "Couldn’t reach Codex")
        }
    }

    static func readCredentials() -> (token: String, accountId: String)? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              let account = tokens["account_id"] as? String
        else { return nil }
        return (token, account)
    }
}

private struct CodexUsage: Decodable {
    let planType: String?
    let rateLimit: CodexRateLimit?
    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexWindow?
    let secondaryWindow: CodexWindow?
    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Double?
    let resetAt: Double?
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    var gauge: UsageGauge {
        UsageGauge(
            label: windowLabel(limitWindowSeconds),
            percent: usedPercent ?? 0,
            resetAt: resetAt.map { Date(timeIntervalSince1970: $0) })
    }
}
