// TLE text parsing for the satpass-tle Worker.
// Mirrors satcore.parseTLEText from the satpass Go CLI: scans for
// line-1/line-2 pairs (so concatenated files with stray blank lines still
// parse) and keys them by NORAD catalog number. First occurrence wins
// (stations catalog is concatenated before amateur).

/**
 * @param {string} text concatenated TLE text (stations + amateur)
 * @returns {Object<string, {name: string, line1: string, line2: string}>}
 */
export function parseTleText(text) {
  const out = {};
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  for (let i = 0; i + 1 < lines.length; i++) {
    const l1 = lines[i].replace(/[ \t]+$/, '');
    const l2 = lines[i + 1].replace(/[ \t]+$/, '');
    if (!l1.startsWith('1 ') || !l2.startsWith('2 ')) continue;
    if (l1.length < 60 || l2.length < 60) continue;
    const norad = l1.substring(2, 7).trim();
    if (!norad || out[norad]) continue;
    let name = 'UNKNOWN';
    if (i > 0) {
      const prev = lines[i - 1].trim();
      if (prev !== '' && !prev.startsWith('1 ') && !prev.startsWith('2 ')) {
        name = prev;
      }
    }
    out[norad] = { name, line1: l1, line2: l2 };
  }
  return out;
}
