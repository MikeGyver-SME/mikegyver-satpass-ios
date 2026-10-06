import Foundation

/// Owns the pass list: TLEs (cached 12 h) → on-device SGP4 → sorted passes.
/// Also drives the 40°+ local-notification scheduling after each refresh.
final class PassStore: ObservableObject {
    static let shared = PassStore()

    enum Phase {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var passes: [SatPass] = []
    @Published private(set) var tleAgeHours: Double?
    @Published private(set) var tleStale: Bool = false
    @Published private(set) var lastUpdated: Date?

    var errorMessage: String? {
        if case .failed(let msg) = phase { return msg }
        return nil
    }

    private init() {}

    /// Next pass across all satellites, if any.
    var nextPass: SatPass? {
        let now = Date()
        return passes.first { $0.los > now }
    }

    func refresh() {
        let settings = SettingsStore.shared
        guard settings.isConfigured else {
            phase = .failed("Add your Worker URL in Settings first.")
            return
        }
        phase = .loading
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let bundle = try await TleStore.load()
                let computed = try PassEngine.shared.compute(
                    tles: bundle.lines,
                    lat: settings.latitude,
                    lon: settings.longitude,
                    hours: settings.windowHours,
                    minElDeg: settings.minElFilter
                )
                await MainActor.run {
                    self.passes = computed
                    self.tleAgeHours = bundle.ageHours
                    self.tleStale = bundle.stale
                    self.lastUpdated = Date()
                    self.phase = .loaded
                }
                if settings.alertsEnabled {
                    await NotificationScheduler.refresh(passes: computed,
                                                        threshold: settings.alertThreshold)
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }
}
