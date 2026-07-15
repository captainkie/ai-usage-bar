import Foundation

/// Fetches Gemini (Google Code Assist) status. Google's tiers are
/// request-based with no published percentage, so this reports the signed-in
/// tier rather than a usage bar. Reads the token from
/// `~/.gemini/oauth_creds.json` (a local file — no Keychain, no prompt).
struct GeminiService {
    func fetch() async -> ProviderCard {
        guard let token = Self.readToken() else {
            return ProviderCard(provider: .gemini, error: "Not signed in — run `gemini`")
        }
        do {
            var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = #"{"metadata":{"pluginType":"GEMINI"}}"#.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return ProviderCard(provider: .gemini, error: "Gemini login expired")
            }
            guard status == 200 else {
                return ProviderCard(provider: .gemini, error: "Couldn’t reach Gemini")
            }

            let tiers = try JSONDecoder().decode(GeminiTiers.self, from: data)
            let tier = tiers.allowedTiers?.first?.name ?? "Gemini Code Assist"
            return ProviderCard(provider: .gemini, note: "\(tier) · unlimited")
        } catch {
            return ProviderCard(provider: .gemini, error: "Couldn’t reach Gemini")
        }
    }

    static func readToken() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String
        else { return nil }
        return token
    }
}

private struct GeminiTiers: Decodable {
    let allowedTiers: [GeminiTier]?
}

private struct GeminiTier: Decodable {
    let name: String?
}
