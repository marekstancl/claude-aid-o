/**
 * Explainer module barrel (EPIC E-047-3_7, Step 9) — spec §6.4.
 *
 * Single import surface for the deterministic Czech explainer: the `explain()`
 * function, the key resolver, the static Czech dictionary, and the contract
 * types. Consumers (WS stream, REST drill-down, `/help`) import from here so the
 * live UI and Help render identical text (§6.4 "shared with frontend").
 */

export { DICTIONARY_CS } from './dictionary.cs.js';
export {
  explain,
  interpolate,
  resolveEntry,
  resolveKeyCandidates,
  setUnknownIdSink,
  MISSING_VAR_PLACEHOLDER,
} from './explain.js';
export type { DictionaryEntry, Explanation, ExplainInput, ExplainKind } from './types.js';

import { DICTIONARY_CS } from './dictionary.cs.js';
import type { DictionaryEntry } from './types.js';

/**
 * The static dictionary as the wire payload for `GET /api/explanations?lang=cs`
 * (§7.4) — `Record<string, DictionaryEntry>`. Help and the FE tooltip layer
 * resolve each entry to a runtime `Explanation` themselves (§13, lib/explain.ts),
 * so the server ships the un-interpolated SOURCE, not pre-rendered text. Deep
 * frozen via the existing const; returned as a typed alias for clarity.
 */
export function getDictionary(lang: 'cs' = 'cs'): Record<string, DictionaryEntry> {
  // Only `cs` exists in MVP1; the param documents the future `.en` seam (§6.4).
  void lang;
  return DICTIONARY_CS;
}
