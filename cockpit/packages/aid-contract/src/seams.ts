// Architecture seam types — stable contracts defined now, wired in MVP2.
// §13.9: TimeSource (time breakdown) and memory taxonomy (Qdrant/vulcan-memory).
// MVP1 ships ONLY these types + stub endpoints; no Qdrant access in MVP1.

// ── TimeSource (§13.9, §5.1) ─────────────────────────────────────────────────
// MetricSet.timeBy slot: MVP1 emits ai/controller with best-effort timeline
// numbers; user/dev are null ("neměřeno"). WakaTime import fills user/dev in
// MVP2 with source:'wakatime' — zero contract churn.
export interface TimeSource {
  kind: 'ai' | 'controller' | 'user' | 'dev';
  durationS: number | null;          // null = "neměřeno"; MVP1 for user/dev and whenever no source
  source: 'timeline' | 'wakatime' | null;  // provenance; null when neměřeno
}

// ── Memory taxonomy (§13.9, §4.7) ────────────────────────────────────────────
// Query/result shapes for reading AID's architectural memory (Qdrant
// clavi_facts_{tenant} via vulcan-memory MCP). MVP1 stub returns
// { available:false, reason:"MVP2", entries:[] } — never touches Qdrant.
// MVP2 wires routes/memory.ts against this stable shape.

export type MemoryScope = 'plan' | 'project' | 'global';
export type MemoryType = 'brain' | 'ideas' | 'reflection' | 'skills' | 'projects';

export interface MemoryQuery {
  query: string;                       // semantic search text
  scope?: MemoryScope;                 // omit = all scopes
  projectId?: string;                  // required when scope='plan'|'project'
  planId?: string;                     // required when scope='plan'
  type?: MemoryType;                   // vulcan-memory type facet
  createdDuringRun?: string;           // run_id filter — "co se naučilo během tohoto běhu"
  topK?: number;                       // result cap (default server-side)
}

export interface MemoryEntry {
  id: string;                          // Qdrant point id
  text: string;                        // the stored fact/idea/reflection
  scope: MemoryScope;
  type: MemoryType;
  projectId: string | null;
  planId: string | null;
  createdDuringRun: string | null;     // run_id this memory was written during (null = unknown/legacy)
  createdAt: string | null;            // ISO-8601 when available
  score: number | null;                // similarity score from query (null when listing, not searching)
}

export interface MemoryResult {        // MVP1 stub always returns available:false
  available: boolean;                  // false in MVP1; true once routes/memory.ts is wired (MVP2)
  reason: string | null;               // "MVP2" in the MVP1 stub; null when available
  entries: MemoryEntry[];              // [] in the MVP1 stub
}
