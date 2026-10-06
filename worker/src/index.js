// satpass-tle: thin TLE proxy for the MikeGyver SatPass iOS app.
//
// The iPhone app does its own pass prediction on-device (JavaScriptCore +
// vendored satellite.js, validated against the satpass Go CLI), so this
// Worker only has one job: fetch the CelesTrak stations + amateur TLE
// catalogs, extract the 5 curated satellites, and cache the parsed result
// for 12 hours. That keeps CelesTrak load polite and gives the app an
// honest TLE age to display.
//
// Resilience: CelesTrak's origin intermittently refuses connections from
// Cloudflare Workers (HTTP 522). Each catalog fetch retries with backoff,
// and if CelesTrak stays unreachable the Worker falls back to the
// tle.ivanstanojevic.me per-satellite API for the 5 curated sats.
//
// Endpoints:
//   GET /        -> health JSON
//   GET /tles    -> { fetchedAt, ageHours, cached, source, sats: {norad: {name, line1, line2}}, missing: [] }
//
// No auth: TLEs are public data. No KV, no Durable Object — the Cache API
// is all the persistence this needs.

import { parseTleText } from './tleparse.js';

const STATIONS_URL = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle';
const AMATEUR_URL = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=tle';
const FALLBACK_URL = (norad) => `https://tle.ivanstanojevic.me/api/tle/${norad}`;
const CACHE_TTL_SECONDS = 12 * 3600; // 12h, matches the satpass CLI disk cache
const USER_AGENT = 'satpass-tle/1.0.1 (MikeGyver Studio; amateur radio pass predictor)';
const VERSION = '1.0.1';

// Curated "work the birds" list — same NORAD IDs as satcore.CuratedSats.
const CURATED = {
  '25544': 'ISS',
  '27607': 'SO-50',
  '43017': 'AO-91',
  '24278': 'FO-29',
  '43803': 'JO-97',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchTleText(url, attempts = 3) {
  let lastError;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': USER_AGENT } });
      if (!res.ok) throw new Error(`CelesTrak HTTP ${res.status} for ${url}`);
      const text = await res.text();
      if (!text.includes('1 ') || !text.includes('2 ')) {
        throw new Error(`CelesTrak response for ${url} did not look like TLE text`);
      }
      return text;
    } catch (e) {
      lastError = e;
      if (i < attempts - 1) await sleep(1000 * (i + 1));
    }
  }
  throw lastError;
}

/// Fallback when CelesTrak is unreachable from Workers: fetch each curated
/// satellite's TLE from the tle.ivanstanojevic.me API.
async function fetchFallbackSats() {
  const sats = {};
  const missing = [];
  const errors = {};
  await Promise.all(
    Object.entries(CURATED).map(async ([norad, shortName]) => {
      try {
        const res = await fetch(FALLBACK_URL(norad), { headers: { 'User-Agent': USER_AGENT } });
        if (!res.ok) throw new Error(`fallback HTTP ${res.status} for ${norad}`);
        const body = await res.json();
        const line1 = (body.line1 || '').trim();
        const line2 = (body.line2 || '').trim();
        if (!line1.startsWith('1 ') || !line2.startsWith('2 ')) {
          throw new Error(`fallback response for ${norad} did not look like TLE lines`);
        }
        sats[norad] = {
          name: shortName,
          tleName: body.name || shortName,
          line1,
          line2,
        };
      } catch (e) {
        missing.push(norad);
        errors[norad] = e.message;
      }
    })
  );
  return { sats, missing, errors };
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/tles') {
      return handleTles();
    }
    return json({
      ok: true,
      service: 'satpass-tle',
      version: VERSION,
      endpoints: ['/tles'],
    });
  },
};

async function handleTles() {
  const cache = caches.default;
  const cacheKey = new Request('https://satpass-tle.internal/tles.json');

  // Serve from cache when fresh; recompute the age honestly on every hit.
  const hit = await cache.match(cacheKey);
  if (hit) {
    const body = await hit.json();
    body.ageHours = Math.round(((Date.now() - Date.parse(body.fetchedAt)) / 3600000) * 10) / 10;
    body.cached = true;
    return json(body);
  }

  // Cache miss: CelesTrak first (stations wins ties), fallback API if unreachable.
  let sats = {};
  let missing = [];
  let source = 'celestrak';
  let fetchError = null;
  let fallbackErrors = {};
  try {
    const [stations, amateur] = await Promise.all([fetchTleText(STATIONS_URL), fetchTleText(AMATEUR_URL)]);
    const parsed = parseTleText(stations + '\n' + amateur);
    for (const [norad, shortName] of Object.entries(CURATED)) {
      if (parsed[norad]) {
        sats[norad] = {
          name: shortName,
          tleName: parsed[norad].name,
          line1: parsed[norad].line1,
          line2: parsed[norad].line2,
        };
      } else {
        missing.push(norad);
      }
    }
  } catch (e) {
    fetchError = e;
    source = 'fallback';
    const fb = await fetchFallbackSats();
    sats = fb.sats;
    missing = fb.missing;
    fallbackErrors = fb.errors;
  }

  if (Object.keys(sats).length === 0) {
    return json(
      {
        ok: false,
        error: `TLE fetch failed: ${fetchError ? fetchError.message : 'all sources failed'}`,
        fallbackErrors,
      },
      502
    );
  }

  const body = {
    ok: true,
    fetchedAt: new Date().toISOString(),
    ageHours: 0,
    cached: false,
    source,
    sats,
    missing,
  };

  const toCache = new Response(JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': `public, max-age=${CACHE_TTL_SECONDS}`,
    },
  });
  // Await the put so a deploy-time failure surfaces instead of silently
  // leaving every request to refetch.
  await cache.put(cacheKey, toCache);
  return json(body);
}
