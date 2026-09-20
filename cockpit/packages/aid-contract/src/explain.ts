import type { StatusKey } from './status.js';

// Static dictionary content — ONE source for both live UI and Help (§6.4, §8.4, §8.2 Help).
export interface DictionaryEntry {
  id: string;
  kind: 'state'|'event'|'cp'|'role'|'verdict'|'severity'|'check'|'concept';
  status: StatusKey;
  headlineTemplate: string;            // one-line, {var}-interpolated by explain()
  detailTemplate: string;              // 1-3 sentences, {var}-interpolated
  term: string;                        // Help display label
  keywords: string[];                  // Help search index
}
// Runtime resolution returned by explain() (§6.4) — distinct from DictionaryEntry.
export interface Explanation {
  headline: string;                    // resolved + interpolated
  detail: string;
  status: StatusKey;                   // drives colour + filter chips
  color: string;                       // resolved CSS var
}
