// aid-ui-facts.mjs — which claims in a page's visible text the facts register does not cover
// (the gate's facts_match row; P103 Step 7, extended by P108 Step 4).
//
// Claims looked for:
//   - phone numbers, prices and times (P103): covered when a register value contains the text,
//     or, for a number of 7+ digits, the same digits;
//   - a percentage ("40 %"): covered when one register entry holds the same number followed by %;
//   - a counted number ("200 klientům", "15 let", "15leté", "200-klientská", "3 projekty"): a number
//     followed (with a space, a hyphen or nothing) by a word of a COUNT_GROUPS group. Covered only
//     when ONE register entry holds the same number as a whole token (no adjacent digit; "2008" does
//     not cover "200"; "2,5" is not "2") AND that entry's key or text holds a word of the same group
//     ("klienti: 200" covers "200 klientům"; "tymy: 200" does not). Years match whole words (let,
//     roků, leté …), so "letadla" or "letáky" are not years;
//   - an e-mail address: covered when it equals a register value.
// Names and references are not checked here (the copy reviewer does that, P108 Step 5).
// An unrelated entry with the same percentage also covers a percentage: a stated limit.

export const FACT_RE = /(\+?\d[\d ]{7,}\d)|(\d[\d  ]*(?:[.,]\d+)?\s?(?:Kč|CZK|€|EUR))|(\b\d{1,2}[:.]\d{2}\b)/g;
const PERCENT_RE = /(\d+(?:[.,]\d+)?)\s?%/g;
const EMAIL_RE = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g;
const COUNT_RE = /(\d[\d  ]*\d|\d)\s*\+?\s*[-‑–]?\s*([a-zA-Zá-žÁ-Ž]+)/g;
// groups by meaning (Czech, Slovak, English): {stems} match a word's start, {words} the whole word
export const COUNT_GROUPS = [
  { stems: ['klient', 'zákazn', 'zakazn', 'client', 'customer'] },   // zákazník, zákazníci, zákazníkům
  { stems: ['projekt', 'project'] },
  { stems: ['člen', 'clen', 'member'] },   // 200členná, 200 členů
  { stems: ['firm', 'společnost', 'spoločnos', 'spolocnos', 'compan'] },
  { words: ['let', 'letech', 'letům', 'letý', 'letá', 'leté', 'letou', 'letého', 'letým', 'letých',
            'rok', 'roku', 'roky', 'roků', 'rokov', 'rokoch', 'rokmi', 'ročné', 'ročný', 'year', 'years'] },
];
const inGroup = (g, w) => (g.stems || []).some(st => w.startsWith(st)) || (g.words || []).includes(w);

export const norm = s => String(s).replace(/[\s  ]+/g, ' ').trim().toLowerCase();
const digits = s => String(s).replace(/\D/g, '');
// the number as written, spaces between digits removed and the decimal comma as a dot: "1 200" -> "1200", "2,5" -> "2.5"
const numTok = s => s.replace(/[\s  ]/g, '').replace(',', '.');

// leaves(facts) — every string/number leaf, normalised (the P103 phone/price/time test reads leaves)
export function leaves(facts) {
  const walk = v => (v && typeof v === 'object') ? Object.values(v).flatMap(walk) : (v === null || v === undefined ? [] : [norm(v)]);
  return walk(facts);
}

// entries(facts) — one text per top-level register entry: its key (for a mapping) and every leaf
export function entries(facts) {
  const leaves = v => (v && typeof v === 'object') ? Object.values(v).flatMap(leaves) : (v === null || v === undefined ? [] : [String(v)]);
  if (Array.isArray(facts)) return facts.map(e => norm(leaves(e).join(' ')));
  if (facts && typeof facts === 'object') return Object.entries(facts).map(([k, v]) => norm(k + ' ' + leaves(v).join(' ')));
  return [];
}

const esc = n => n.replace('.', '[.,]');
const hasNumber = (entry, n) => new RegExp(`(^|[^0-9.,])${esc(n)}(?![0-9])(?![.,][0-9])`).test(entry.replace(/(\d)[\s  ](?=\d)/g, '$1'));
const groupOf = word => COUNT_GROUPS.find(g => inGroup(g, word));

// unknownClaims(text, facts) — the claims of the text no register entry covers, unique, in order
export function unknownClaims(text, facts) {
  const es = entries(facts), lv = leaves(facts);
  const out = [];
  for (const m of text.matchAll(FACT_RE)) {   // P103: each leaf on its own, as before
    const t = m[0].trim(), n = norm(t), d = digits(t);
    if (!lv.some(f => f.includes(n) || (d.length >= 7 && digits(f).includes(d)))) out.push(t);
  }
  for (const m of text.matchAll(PERCENT_RE)) {
    const n = numTok(m[1]);
    if (!es.some(e => new RegExp(`(^|[^0-9.,])${esc(n)}\\s?%`).test(e))) out.push(m[0].trim());
  }
  for (const m of text.matchAll(COUNT_RE)) {
    const word = m[2].toLowerCase(), g = groupOf(word);
    if (!g) continue;
    const n = numTok(m[1]);
    if (!es.some(e => hasNumber(e, n) && e.split(/[^a-zá-ž]+/).some(w => inGroup(g, w)))) out.push(m[0].trim());
  }
  for (const m of text.matchAll(EMAIL_RE)) {
    const e = m[0].toLowerCase();
    if (!lv.some(x => x === e)) out.push(m[0]);
  }
  return [...new Set(out)];
}
