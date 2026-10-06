// Smoke test for the satpass-tle Worker (runs locally with plain node).
// Fetches the live CelesTrak catalogs exactly like the Worker does and
// checks that the shared parseTleText() finds all 5 curated satellites.
// Run: npm test   (from worker/)
import { parseTleText } from '../src/tleparse.js';

const STATIONS_URL = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle';
const AMATEUR_URL = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=tle';
const WANT = ['25544', '27607', '43017', '24278', '43803'];

async function get(url) {
  const r = await fetch(url, { headers: { 'User-Agent': 'satpass-tle-smoke/1.0.0' } });
  if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
  return r.text();
}

const [st, am] = await Promise.all([get(STATIONS_URL), get(AMATEUR_URL)]);
const parsed = parseTleText(st + '\n' + am);
let failed = false;
for (const norad of WANT) {
  const t = parsed[norad];
  if (!t) {
    console.error(`MISSING TLE for NORAD ${norad}`);
    failed = true;
    continue;
  }
  const ok1 = t.line1.startsWith('1 ') && t.line1.length >= 60;
  const ok2 = t.line2.startsWith('2 ') && t.line2.length >= 60;
  console.log(`${norad} ${t.name}: line1 ${ok1 ? 'ok' : 'BAD'}, line2 ${ok2 ? 'ok' : 'BAD'}`);
  if (!ok1 || !ok2) failed = true;
}
console.log(failed ? 'SMOKE TEST FAILED' : `SMOKE TEST PASSED (${Object.keys(parsed).length} TLEs parsed)`);
process.exit(failed ? 1 : 0);
