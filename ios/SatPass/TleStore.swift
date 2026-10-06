import Foundation

/// TLE disk cache with the same 12-hour freshness rule as the satpass Go
/// CLI. On a refresh the app uses the cached TLEs when they are fresh, and
/// only hits the Worker when the cache is stale or missing. If the Worker
/// is unreachable but a stale cache exists, the stale TLEs are used and
/// flagged honestly in the UI instead of failing outright.
enum TleStore {
    struct Bundle {
        /// NORAD -> TLE lines, ready for the pass engine.
        let lines: [String: EngineTleLines]
        let fetchedAt: Date
        let ageHours: Double
        let fromCache: Bool
        /// True when served from a cache older than 12h (Worker unreachable).
        let stale: Bool
    }

    enum TleError: LocalizedError {
        case notConfigured
        case noData(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add your Worker URL in Settings first."
            case .noData(let why):
                return "No TLE data: \(why)"
            }
        }
    }

    static let maxAgeHours = 12.0

    private struct CachedFile: Codable {
        let fetchedAt: Date
        let sats: [String: EngineTleLines]
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("satpass-tles.json")
    }

    private static func readCache() -> CachedFile? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedFile.self, from: data)
    }

    private static func writeCache(_ file: CachedFile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(file) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func ageHours(since date: Date) -> Double {
        Date().timeIntervalSince(date) / 3600
    }

    static func load() async throws -> Bundle {
        let settings = SettingsStore.shared
        guard settings.isConfigured else { throw TleError.notConfigured }

        if let cached = readCache() {
            let age = ageHours(since: cached.fetchedAt)
            if age < maxAgeHours, !cached.sats.isEmpty {
                return Bundle(lines: cached.sats, fetchedAt: cached.fetchedAt,
                              ageHours: age, fromCache: true, stale: false)
            }
        }

        // Cache stale or missing: fetch live from the Worker.
        do {
            let (fetchedAt, sats, _) = try await ApiClient.fetchTles(baseURL: settings.baseURL)
            var lines: [String: EngineTleLines] = [:]
            for (norad, entry) in sats {
                lines[norad] = EngineTleLines(line1: entry.line1, line2: entry.line2)
            }
            guard !lines.isEmpty else { throw TleError.noData("Worker returned no satellites") }
            writeCache(CachedFile(fetchedAt: fetchedAt, sats: lines))
            return Bundle(lines: lines, fetchedAt: fetchedAt,
                          ageHours: ageHours(since: fetchedAt), fromCache: false, stale: false)
        } catch {
            // Worker unreachable: fall back to the stale cache if there is one.
            if let cached = readCache(), !cached.sats.isEmpty {
                return Bundle(lines: cached.sats, fetchedAt: cached.fetchedAt,
                              ageHours: ageHours(since: cached.fetchedAt),
                              fromCache: true, stale: true)
            }
            throw TleError.noData(error.localizedDescription)
        }
    }

    /// Clears the disk cache (Settings → "Clear TLE cache" forces a refetch).
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
