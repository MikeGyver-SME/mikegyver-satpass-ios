// passengine.js — on-device pass prediction for MikeGyver SatPass.
//
// Runs inside iOS JavaScriptCore. Requires the `satellite` global from
// satellite.js v5.0.0 (satellite.min.js, MIT) to be evaluated first.
//
//   SatPassEngine.computePasses(tleJson, optsJson) -> JSON string
//
// tleJson:  {"25544": {"line1": "...", "line2": "..."}, ...}  (from /tles)
// optsJson: {"lat": 29.9767, "lon": -95.6169, "altKm": 0.06,
//            "hours": 48, "horizonDeg": 0, "minElDeg": 10, "nowMs": 1699...}
//
// Returns: {"computedAt": iso, "passes": [
//   {"norad": "25544", "aos": iso, "tca": iso, "los": iso,
//    "maxEl": 45.5, "azAos": 310, "azLos": 120, "durMin": 9.5,
//    "inProgress": false}, ... ]} sorted by AOS.
//
// Algorithm mirrors satcore/passes.go in the satpass Go CLI: sample
// elevation every 30 s, find above-horizon intervals, refine AOS/LOS by
// bisection (40 iters) and TCA by golden-section search (60 iters).
// Validated 2026-10-03: 26/26 passes identical to the CLI (gosgp4) over
// 48 h — AOS within 1 s, max elevation within 0.1 deg.

(function () {
  'use strict';

  var DEG2RAD = Math.PI / 180;
  var RAD2DEG = 180 / Math.PI;

  function elevation(satrec, date, latDeg, lonDeg, altKm) {
    var pv = satellite.propagate(satrec, date);
    if (!pv || !pv.position) return -90;
    var gmst = satellite.gstime(date);
    var satEcf = satellite.eciToEcf(pv.position, gmst);
    var obsGd = { latitude: latDeg * DEG2RAD, longitude: lonDeg * DEG2RAD, height: altKm };
    var look = satellite.ecfToLookAngles(obsGd, satEcf);
    return look.elevation * RAD2DEG;
  }

  function azimuth(satrec, date, latDeg, lonDeg, altKm) {
    var pv = satellite.propagate(satrec, date);
    if (!pv || !pv.position) return 0;
    var gmst = satellite.gstime(date);
    var satEcf = satellite.eciToEcf(pv.position, gmst);
    var obsGd = { latitude: latDeg * DEG2RAD, longitude: lonDeg * DEG2RAD, height: altKm };
    var look = satellite.ecfToLookAngles(obsGd, satEcf);
    return look.azimuth * RAD2DEG;
  }

  function bisectCrossing(satrec, t0, t1, level, lat, lon, alt) {
    for (var i = 0; i < 40; i++) {
      var mid = (t0 + t1) / 2;
      if (elevation(satrec, new Date(mid), lat, lon, alt) < level) t0 = mid;
      else t1 = mid;
    }
    return t1;
  }

  function maxElevation(satrec, t0, t1, lat, lon, alt) {
    var gr = 0.618033988749895;
    var a = t0, b = t1;
    var c = b - gr * (b - a), d = a + gr * (b - a);
    for (var i = 0; i < 60; i++) {
      if (elevation(satrec, new Date(c), lat, lon, alt) > elevation(satrec, new Date(d), lat, lon, alt)) b = d;
      else a = c;
      c = b - gr * (b - a);
      d = a + gr * (b - a);
    }
    var tca = (a + b) / 2;
    return { tca: tca, maxEl: elevation(satrec, new Date(tca), lat, lon, alt) };
  }

  function findPasses(satrec, norad, startMs, endMs, horizonDeg, minElDeg, lat, lon, alt) {
    var step = 30000; // 30 s sampling, like the CLI
    var n = Math.floor((endMs - startMs) / step) + 1;
    var els = new Array(n), ts = new Array(n);
    for (var i = 0; i < n; i++) {
      ts[i] = startMs + i * step;
      els[i] = elevation(satrec, new Date(ts[i]), lat, lon, alt);
    }
    var passes = [];
    var i = 0;
    while (i < n) {
      if (els[i] <= horizonDeg) { i++; continue; }
      var j = i;
      while (j < n && els[j] > horizonDeg) j++;
      var inProgress = (i === 0);
      var aos = inProgress ? startMs : bisectCrossing(satrec, ts[i - 1], ts[i], horizonDeg, lat, lon, alt);
      var los = (j >= n) ? endMs : bisectCrossing(satrec, ts[j], ts[j - 1], horizonDeg, lat, lon, alt);
      var mm = maxElevation(satrec, aos, los, lat, lon, alt);
      if (mm.maxEl >= minElDeg) {
        passes.push({
          norad: norad,
          aos: new Date(aos).toISOString(),
          tca: new Date(mm.tca).toISOString(),
          los: new Date(los).toISOString(),
          maxEl: Math.round(mm.maxEl * 10) / 10,
          azAos: Math.round(azimuth(satrec, new Date(aos), lat, lon, alt)),
          azLos: Math.round(azimuth(satrec, new Date(los), lat, lon, alt)),
          durMin: Math.round(((los - aos) / 60000) * 10) / 10,
          inProgress: inProgress
        });
      }
      i = j;
    }
    return passes;
  }

  function computePasses(tleJson, optsJson) {
    var tles, opts;
    try {
      tles = JSON.parse(tleJson);
      opts = JSON.parse(optsJson);
    } catch (e) {
      return JSON.stringify({ ok: false, error: 'bad JSON input: ' + e.message });
    }
    var lat = opts.lat, lon = opts.lon;
    var altKm = (typeof opts.altKm === 'number') ? opts.altKm : 0.06;
    var hours = (typeof opts.hours === 'number') ? opts.hours : 48;
    var horizonDeg = (typeof opts.horizonDeg === 'number') ? opts.horizonDeg : 0;
    var minElDeg = (typeof opts.minElDeg === 'number') ? opts.minElDeg : 10;
    var startMs = (typeof opts.nowMs === 'number') ? opts.nowMs : Date.now();
    var endMs = startMs + hours * 3600 * 1000;

    var all = [];
    var errors = [];
    var norads = Object.keys(tles).sort();
    for (var k = 0; k < norads.length; k++) {
      var norad = norads[k];
      var t = tles[norad];
      if (!t || !t.line1 || !t.line2) { errors.push(norad + ': missing TLE lines'); continue; }
      var satrec;
      try {
        satrec = satellite.twoline2satrec(t.line1, t.line2);
      } catch (e) {
        errors.push(norad + ': TLE parse failed: ' + e.message);
        continue;
      }
      var ps = findPasses(satrec, norad, startMs, endMs, horizonDeg, minElDeg, lat, lon, altKm);
      for (var p = 0; p < ps.length; p++) all.push(ps[p]);
    }
    all.sort(function (a, b) { return a.aos < b.aos ? -1 : (a.aos > b.aos ? 1 : 0); });
    return JSON.stringify({ ok: true, computedAt: new Date(startMs).toISOString(), passes: all, errors: errors });
  }

  // Export for JavaScriptCore (global) and for node-based validation.
  var api = { computePasses: computePasses };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  } else {
    this.SatPassEngine = api; // jshint ignore:line
  }
}).call(typeof globalThis !== 'undefined' ? globalThis : this);
