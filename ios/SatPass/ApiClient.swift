import Foundation

/// Thin client for the satpass-tle Cloudflare Worker.
enum ApiClient {
    struct TleEntry: Decodable {
        let name: String
        let tleName: String?
        let line1: String
        let line2: String
    }

    struct TleResponse: Decodable {
        let ok: Bool
        let fetchedAt: String
        let sats: [String: TleEntry]
        let missing: [String]
    }

    enum ApiError: LocalizedError {
        case badURL
        case httpError(Int)
        case serverError(String)
        case decodeError(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "The Worker URL doesn't look right."
            case .httpError(let code): return "Worker returned HTTP \(code)."
            case .serverError(let msg): return "Worker error: \(msg)"
            case .decodeError(let msg): return "Couldn't read the Worker response: \(msg)"
            }
        }
    }

    /// GET {base}/tles — used for both the connection test and real fetches.
    static func fetchTles(baseURL: String) async throws -> (fetchedAt: Date, sats: [String: TleEntry], missing: [String]) {
        guard let url = URL(string: baseURL + "/tles") else { throw ApiError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.setValue("satpass-ios/1.0.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ApiError.httpError(-1) }
        guard http.statusCode == 200 else { throw ApiError.httpError(http.statusCode) }
        let decoder = JSONDecoder()
        let decoded: TleResponse
        do {
            decoded = try decoder.decode(TleResponse.self, from: data)
        } catch {
            throw ApiError.decodeError(error.localizedDescription)
        }
        guard decoded.ok else { throw ApiError.serverError("ok=false") }
        guard let fetchedAt = DateFormats.parseISO(decoded.fetchedAt) else {
            throw ApiError.decodeError("bad fetchedAt timestamp")
        }
        return (fetchedAt, decoded.sats, decoded.missing)
    }

    /// Lightweight connection test for the Settings screen.
    static func testConnection(baseURL: String) async throws -> Int {
        let (_, sats, _) = try await fetchTles(baseURL: baseURL)
        return sats.count
    }
}
