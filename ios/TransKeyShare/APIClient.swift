import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case featureDisabled
    case deviceLimit
    case quotaExceeded
    case rateLimited
    case textTooLong
    case maintenance
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please open the app to log in again."
        case .featureDisabled: return "This feature requires a paid plan."
        case .deviceLimit: return "Too many devices on free plan. Please upgrade."
        case .quotaExceeded: return "Daily quota exceeded. Try again tomorrow or upgrade."
        case .rateLimited: return "Too many requests. Please wait a moment."
        case .textTooLong: return "Text is too long."
        case .maintenance: return "Server is under maintenance. Please try again later."
        case .networkError(let msg): return msg
        case .unknown(let msg): return msg
        }
    }
}

class APIClient {

    private let store = AppGroupStore.shared

    private var baseURL: String { store.apiBaseURL }

    private func makeRequest(endpoint: String, body: [String: Any]? = nil) -> URLRequest? {
        guard let token = store.token, !token.isEmpty else { return nil }
        guard let deviceID = store.deviceID, !deviceID.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        request.setValue("mobile", forHTTPHeaderField: "X-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    func translate(
        text: String,
        targetLang: String,
        sourceLang: String? = nil,
        isReply: Bool = false
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["text": text, "targetLang": targetLang]
        if let src = sourceLang, src != "auto" { body["sourceLang"] = src }
        if isReply { body["isReply"] = true }
        return try await performRequest(endpoint: "/translate", body: body)
    }

    func summarize(text: String, targetLang: String) async throws -> [String: Any] {
        return try await performRequest(endpoint: "/summarize", body: ["text": text, "targetLang": targetLang])
    }

    func explain(text: String, targetLang: String) async throws -> [String: Any] {
        return try await performRequest(endpoint: "/explain", body: ["text": text, "targetLang": targetLang])
    }

    func refine(text: String) async throws -> [String: Any] {
        return try await performRequest(endpoint: "/refine", body: ["text": text])
    }

    private func performRequest(endpoint: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let request = makeRequest(endpoint: endpoint, body: body) else {
            throw APIError.unauthorized
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        if http.statusCode == 403 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let code = json["code"] as? String ?? json["error"] as? String ?? ""
                if code == "feature_disabled" { throw APIError.featureDisabled }
                if code == "device_limit" { throw APIError.deviceLimit }
            }
            throw APIError.featureDisabled
        }
        if http.statusCode == 413 {
            throw APIError.textTooLong
        }
        if http.statusCode == 429 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let code = json["code"] as? String ?? ""
                if code == "quota_exceeded" { throw APIError.quotaExceeded }
            }
            throw APIError.rateLimited
        }
        if http.statusCode == 503 {
            throw APIError.maintenance
        }
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw APIError.unknown("Error \(http.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.unknown("Invalid response body")
        }

        return json
    }
}
