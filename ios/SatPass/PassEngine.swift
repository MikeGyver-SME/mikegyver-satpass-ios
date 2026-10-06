import Foundation
import JavaScriptCore

/// Runs the vendored SGP4 pass engine (satellite.js + passengine.js) inside
/// JavaScriptCore. The exact shipped JS files were validated on 2026-10-03
/// against the satpass Go CLI: 26/26 passes identical over 48 h, AOS within
/// 1 s, max elevation within 0.1°.
///
/// All JSContext access is serialised on a private queue — JSContext is not
/// thread-safe.
final class PassEngine {
    static let shared = PassEngine()

    enum EngineError: LocalizedError {
        case scriptMissing(String)
        case initFailed(String)
        case computeFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing(let name): return "Bundled script missing: \(name)"
            case .initFailed(let why): return "Pass engine failed to start: \(why)"
            case .computeFailed(let why): return "Pass computation failed: \(why)"
            }
        }
    }

    private let queue = DispatchQueue(label: "studio.mikegyver.satpass.passengine")
    private var context: JSContext?

    private init() {}

    private func ensureContext() throws -> JSContext {
        if let ctx = context { return ctx }
        guard let satURL = Bundle.main.url(forResource: "satellite.min", withExtension: "js") else {
            throw EngineError.scriptMissing("satellite.min.js")
        }
        guard let engineURL = Bundle.main.url(forResource: "passengine", withExtension: "js") else {
            throw EngineError.scriptMissing("passengine.js")
        }
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, exc in
            // Surfaced below via the ok=false envelope; kept for debugging.
            print("SatPass JS exception: \(exc?.toString() ?? "unknown")")
        }
        do {
            let satSrc = try String(contentsOf: satURL, encoding: .utf8)
            let engineSrc = try String(contentsOf: engineURL, encoding: .utf8)
            ctx.evaluateScript(satSrc, withSourceURL: satURL)
            ctx.evaluateScript(engineSrc, withSourceURL: engineURL)
        } catch {
            throw EngineError.initFailed(error.localizedDescription)
        }
        guard ctx.objectForKeyedSubscript("SatPassEngine")?.isUndefined == false else {
            throw EngineError.initFailed("SatPassEngine global not found after loading scripts")
        }
        context = ctx
        return ctx
    }

    /// Computes passes for the given TLEs. Safe to call from any thread;
    /// blocks the caller's thread for ~1 s (48 h × 5 sats on iPhone-class HW).
    func compute(tles: [String: EngineTleLines],
                 lat: Double, lon: Double, altKm: Double = 0.06,
                 hours: Double, horizonDeg: Double = 0, minElDeg: Double,
                 now: Date = Date()) throws -> [SatPass] {
        try queue.sync {
            let ctx = try ensureContext()

            var tleDict: [String: [String: String]] = [:]
            for (norad, lines) in tles {
                tleDict[norad] = ["line1": lines.line1, "line2": lines.line2]
            }
            let tleData = try JSONSerialization.data(withJSONObject: tleDict)
            let tleJson = String(data: tleData, encoding: .utf8) ?? "{}"
            let opts: [String: Any] = [
                "lat": lat, "lon": lon, "altKm": altKm,
                "hours": hours, "horizonDeg": horizonDeg, "minElDeg": minElDeg,
                "nowMs": now.timeIntervalSince1970 * 1000,
            ]
            let optsData = try JSONSerialization.data(withJSONObject: opts)
            let optsJson = String(data: optsData, encoding: .utf8) ?? "{}"

            guard let fn = ctx.objectForKeyedSubscript("SatPassEngine")?
                    .objectForKeyedSubscript("computePasses"),
                  fn.isUndefined == false else {
                throw EngineError.computeFailed("computePasses not found")
            }
            guard let resultString = fn.call(withArguments: [tleJson, optsJson])?.toString() else {
                throw EngineError.computeFailed("no result from computePasses")
            }
            guard let resultData = resultString.data(using: .utf8) else {
                throw EngineError.computeFailed("result was not UTF-8")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { d in
                let s = try d.singleValueContainer().decode(String.self)
                if let date = DateFormats.parseISO(s) { return date }
                throw DecodingError.dataCorrupted(
                    .init(codingPath: d.codingPath, debugDescription: "bad date: \(s)"))
            }
            let result: EngineResult
            do {
                result = try decoder.decode(EngineResult.self, from: resultData)
            } catch {
                throw EngineError.computeFailed("could not decode result: \(error.localizedDescription)")
            }
            guard result.ok else {
                throw EngineError.computeFailed(result.errors.joined(separator: "; "))
            }
            return result.passes.map(SatPass.init(from:))
        }
    }
}
