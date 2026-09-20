import type { StatusKey } from '@aid/contract';

/**
 * Presentational compliance-matrix shape (Screen E, §13).
 *
 * Deliberately a thin, server-agnostic projection: the data layer (a later step)
 * folds `ComplianceView`/`ComplianceRun` into rows × checks. A cell is honest
 * about absence — `null` means "this project has no recorded result for this
 * check" and renders as "N/A" (grey), NEVER 0% or a fabricated fail.
 */
export type ComplianceCellState = 'pass' | 'fail' | null;

export interface ComplianceCell {
  /** The check column id this cell belongs to. */
  check: string;
  /** pass | fail | null (null = not recorded → "N/A", never 0%/fail). */
  state: ComplianceCellState;
  /** Optional short evidence/gloss for the tooltip. */
  evidence?: string | null;
}

export interface ComplianceMatrixRow {
  projectId: string;
  projectName: string;
  /** One cell per check column (in the same order as `checks`). */
  cells: ComplianceCell[];
}

export interface ComplianceMatrixData {
  /** Ordered check column ids. */
  checks: string[];
  rows: ComplianceMatrixRow[];
}

/** Map a cell state to its §6.2 STATUS token. `null` → idle/grey (N/A). */
export function cellStatus(state: ComplianceCellState): StatusKey {
  if (state === 'pass') return 'proslo';
  if (state === 'fail') return 'selhalo';
  return 'necinne';
}

/** Czech word for a cell. `null` → "N/A" (never 0%, never a fabricated pass/fail). */
export function cellLabel(state: ComplianceCellState): string {
  if (state === 'pass') return 'prošlo';
  if (state === 'fail') return 'selhalo';
  return 'N/A';
}
