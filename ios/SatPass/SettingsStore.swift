import Foundation

/// App settings, persisted in UserDefaults. Mirrors the WalkLog pattern:
/// the Worker URL is required before the app can do anything.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var workerURL: String {
        didSet { UserDefaults.standard.set(workerURL, forKey: "satpass.workerURL") }
    }
    @Published var latitude: Double {
        didSet { UserDefaults.standard.set(latitude, forKey: "satpass.latitude") }
    }
    @Published var longitude: Double {
        didSet { UserDefaults.standard.set(longitude, forKey: "satpass.longitude") }
    }
    @Published var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "satpass.alertsEnabled") }
    }
    /// Max-elevation threshold (deg) for the 10-minute heads-up. Default 40.
    @Published var alertThreshold: Double {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: "satpass.alertThreshold") }
    }
    /// Only passes peaking at/above this elevation are listed. Default 10.
    @Published var minElFilter: Double {
        didSet { UserDefaults.standard.set(minElFilter, forKey: "satpass.minElFilter") }
    }
    /// Prediction window in hours. Default 48.
    @Published var windowHours: Double {
        didSet { UserDefaults.standard.set(windowHours, forKey: "satpass.windowHours") }
    }

    private init() {
        let d = UserDefaults.standard
        workerURL = d.string(forKey: "satpass.workerURL") ?? ""
        latitude = d.object(forKey: "satpass.latitude") as? Double ?? 29.9767
        longitude = d.object(forKey: "satpass.longitude") as? Double ?? -95.6169
        alertsEnabled = d.object(forKey: "satpass.alertsEnabled") as? Bool ?? false
        alertThreshold = d.object(forKey: "satpass.alertThreshold") as? Double ?? 40
        minElFilter = d.object(forKey: "satpass.minElFilter") as? Double ?? 10
        windowHours = d.object(forKey: "satpass.windowHours") as? Double ?? 48
    }

    var isConfigured: Bool {
        !workerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Normalised base URL without a trailing slash.
    var baseURL: String {
        var s = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
