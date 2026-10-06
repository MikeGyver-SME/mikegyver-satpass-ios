import Foundation
import SwiftUI

// MARK: - Brand

enum Brand {
    /// MikeGyver navy
    static let navy = Color(red: 10 / 255, green: 31 / 255, blue: 68 / 255)
    /// MikeGyver gold
    static let gold = Color(red: 232 / 255, green: 182 / 255, blue: 42 / 255)
}

// MARK: - Satellite guide data
//
// Static frequency guide, transcribed from satcore/sats.go in the satpass Go
// CLI (frequencies verified against AMSAT and work-sat.com, Sep 2026), plus
// FT-65R-specific cheat-sheet lines for Mike's handheld.

struct SatGuide: Identifiable {
    var id: String { norad }
    let norad: String
    let shortName: String
    let fullName: String
    let mode: String
    let uplink: String
    let downlink: String
    let notes: String
    /// One-line "listen" hint used in notification bodies.
    let alertLine: String
    /// FT-65R cheat-sheet bullets shown on the pass detail screen.
    let ft65r: [String]
    /// True for the linear birds: the FM-only FT-65R cannot work these.
    let needsSSB: Bool

    static let all: [SatGuide] = [
        SatGuide(
            norad: "25544",
            shortName: "ISS",
            fullName: "ISS",
            mode: "FM voice / packet",
            uplink: "144.490 MHz FM (Region 2/3 voice); 145.825 MHz FM (packet/APRS digipeater)",
            downlink: "145.800 MHz FM (crew voice/SSTV); 145.825 MHz FM (packet); 437.800 MHz FM (crossband repeater down)",
            notes: "Crossband repeater uplink 145.990 MHz (67.0 Hz tone). Crew voice most common on 145.800 down.",
            alertLine: "Listen: 145.800 MHz FM",
            ft65r: [
                "Crew voice: 145.800 MHz FM — park here and leave it",
                "Packet/APRS digipeater: 145.825 MHz FM",
                "2m Doppler is only ±3 kHz — no tuning needed on FM",
                "Receive-only until the call sign arrives: no PTT, not even a test",
            ],
            needsSSB: false
        ),
        SatGuide(
            norad: "27607",
            shortName: "SO-50",
            fullName: "SO-50 (SAUDISAT 1C)",
            mode: "FM voice",
            uplink: "145.850 MHz FM (67.0 Hz; transmit 74.4 Hz briefly to arm the 10-min timer)",
            downlink: "436.795 MHz FM (tune 436.805 → 436.785 across the pass for Doppler)",
            notes: "Arm with 74.4 Hz tone, then work with 67.0 Hz. 2m up / 70cm down.",
            alertLine: "Down: 436.795 MHz FM (tune 436.805 → 436.785)",
            ft65r: [
                "Downlink 436.795 MHz FM — tune 436.805 → 436.795 → 436.785 across the pass",
                "Use VFO mode with 5 kHz steps on 70cm; the 2m side barely moves",
                "Uplink 145.850 MHz FM, 67.0 Hz tone (for after you're licensed)",
                "Arm the bird first: 74.4 Hz briefly to start its 10-minute timer",
            ],
            needsSSB: false
        ),
        SatGuide(
            norad: "43017",
            shortName: "AO-91",
            fullName: "AO-91 (FOX-1B / RadFxSat)",
            mode: "FM voice",
            uplink: "435.250 MHz FM (67.0 Hz; tune 435.240 → 435.260 across the pass for Doppler)",
            downlink: "145.960 MHz FM",
            notes: "70cm up / 2m down. Strong downlink, great first bird.",
            alertLine: "Down: 145.960 MHz FM",
            ft65r: [
                "Downlink 145.960 MHz FM — park here, it's a strong signal",
                "Uplink 435.250 MHz FM, 67.0 Hz — tune 435.240 → 435.250 → 435.260 (licensed use)",
                "70cm up / 2m down — the reverse of SO-50",
                "Great first bird: loud downlink, easy on the stock whip",
            ],
            needsSSB: false
        ),
        SatGuide(
            norad: "24278",
            shortName: "FO-29",
            fullName: "FO-29 (JAS-2)",
            mode: "Linear SSB/CW",
            uplink: "145.900–146.000 MHz LSB",
            downlink: "435.800–435.900 MHz USB (inverting); CW beacon 435.795 MHz",
            notes: "Inverting transponder. Keep uplink power low (QRP) to avoid capturing it.",
            alertLine: "SSB linear — not workable on the FM-only FT-65R",
            ft65r: [
                "Linear SSB transponder — the FM-only FT-65R cannot work this bird",
                "Catch the SSB downlink on VibeSDR instead",
                "Uplink 145.900–146.000 MHz LSB; downlink 435.800–435.900 MHz USB (inverting)",
                "CW beacon 435.795 MHz",
            ],
            needsSSB: true
        ),
        SatGuide(
            norad: "43803",
            shortName: "JO-97",
            fullName: "JO-97 (JY1SAT)",
            mode: "Linear SSB/CW",
            uplink: "435.100–435.120 MHz LSB",
            downlink: "145.855–145.875 MHz USB (inverting)",
            notes: "Small, easy linear bird for SSB practice.",
            alertLine: "SSB linear — not workable on the FM-only FT-65R",
            ft65r: [
                "Linear SSB transponder — the FM-only FT-65R cannot work this bird",
                "Catch the SSB downlink on VibeSDR instead",
                "Uplink 435.100–435.120 MHz LSB; downlink 145.855–145.875 MHz USB (inverting)",
            ],
            needsSSB: true
        ),
    ]

    static func guide(for norad: String) -> SatGuide? {
        all.first { $0.norad == norad }
    }
}

// MARK: - Engine JSON (from passengine.js)

struct EngineTleLines: Codable {
    let line1: String
    let line2: String
}

struct EnginePass: Decodable {
    let norad: String
    let aos: Date
    let tca: Date
    let los: Date
    let maxEl: Double
    let azAos: Double
    let azLos: Double
    let durMin: Double
    let inProgress: Bool
}

struct EngineResult: Decodable {
    let ok: Bool
    let computedAt: Date
    let passes: [EnginePass]
    let errors: [String]
}

// MARK: - UI model

struct SatPass: Identifiable {
    var id: String { "\(norad)-\(Int(aos.timeIntervalSince1970))" }
    let norad: String
    let guide: SatGuide
    let aos: Date
    let tca: Date
    let los: Date
    let maxEl: Double
    let azAos: Double
    let azLos: Double
    let durMin: Double
    let inProgress: Bool

    /// Mike's standing alert threshold: 40°+ max elevation.
    var isPrime: Bool { maxEl >= 40 }

    var notifyDate: Date { aos.addingTimeInterval(-10 * 60) }

    init(from engine: EnginePass) {
        norad = engine.norad
        guide = SatGuide.guide(for: engine.norad)
            ?? SatGuide(norad: engine.norad, shortName: engine.norad, fullName: engine.norad,
                        mode: "—", uplink: "—", downlink: "—", notes: "",
                        alertLine: "", ft65r: [], needsSSB: false)
        aos = engine.aos
        tca = engine.tca
        los = engine.los
        maxEl = engine.maxEl
        azAos = engine.azAos
        azLos = engine.azLos
        durMin = engine.durMin
        inProgress = engine.inProgress
    }
}

// MARK: - Date helpers

enum DateFormats {
    /// Parses the ISO strings passengine.js emits (always with millis, UTC).
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoNoMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        iso.date(from: s) ?? isoNoMillis.date(from: s)
    }

    /// "Sat 3:25 PM" in the device's local timezone.
    static let passTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    /// "Sat, Oct 4" for section headers.
    static let passDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E, MMM d"
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

extension Date {
    var passTimeString: String { DateFormats.passTime.string(from: self) }
    var passDayString: String { DateFormats.passDay.string(from: self) }
    var relativeString: String { DateFormats.relative.localizedString(for: self, relativeTo: Date()) }
    /// True when two dates fall on the same calendar day (device timezone).
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}
