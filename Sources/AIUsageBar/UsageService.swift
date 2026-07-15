import Foundation

enum UsageServiceError: LocalizedError {
    case badResponse
    case unauthorized
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Unexpected response from Anthropic"
        case .unauthorized:
            return "Login expired — open Claude Code to refresh"
        case .http(let code):
            return "Anthropic returned HTTP \(code)"
        }
    }
}

/// Talks to Anthropic's official OAuth usage endpoint — the only network
/// call this app ever makes.
struct UsageService {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("AIUsageBar/0.1 (self-hosted)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageServiceError.badResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageServiceError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw UsageServiceError.http(http.statusCode)
        }

        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}
