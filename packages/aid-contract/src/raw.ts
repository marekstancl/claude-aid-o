// Raw snake_case contract layer — mirrors v3 disk shapes exactly.
// Consumers: file parsers, watcher, FSM reader. Never consumed by frontend directly.

export type AidFsmState = "READY" | "EXECUTE" | "GATES" | "ESCALATION" | "DONE" | "ERROR";
// ^^^ Line 1 mandatory: 6-state union (adds "ERROR" to the existing 5-state union)

export type AidMode = "manual" | "auto";

export type AidGateResult = "pass" | "fail" | "skipped";

export interface AidStateYaml {
  epic_id: string;
  run_id: string;
  state: AidFsmState;
  current_step: number;
  total_steps: number;
  mode: AidMode;
  branch: string;
  base_commit: string;
  gate_retries: number;
  escalation_count: number;
  started_at: string; // ISO 8601
  // §4.1-reliable conditional fields — present only in specific FSM states:
  done_phase?: string;
  streamlined_mode?: boolean;
  plan_path?: string | null;
  plan_json_hash?: string;
  pm_decision?: string; // §4.0 finding #2: conditional, present only post-merge
}

export interface AidTimelineEntry {
  ts: string;        // ISO 8601
  event: string;     // "step_dispatch" | "step_complete" | "gate_run" | ...
  state?: AidFsmState;
  step_id?: string;
  role?: string;
  model?: string;
  result?: "pass" | "fail";
  duration_s?: number;
  [key: string]: unknown;
}

export interface AidGateDetail {
  result: AidGateResult;
  exit_code: number;
  duration_ms: number;
  output: string;
  attempts: number;
}

export interface AidGatesReport {
  epic_id: string;
  run_id: string;
  overall: "pass" | "fail";
  completed_at: string;
  gates: Record<string, AidGateDetail>;
}

export interface AidQuickLog {
  id: string;             // Q-001
  task: string;
  started_at: string;
  duration_s: number;
  files_changed: string[];
  commit: string;
  escalated_to_epic: boolean;
}

export interface AidProjectYaml {
  name: string;
  type: "web-app" | "cli" | "library" | "service" | "fullstack";
  languages: string[];
  test_command?: string;
  lint_command?: string;
  build_command?: string;
  framework?: string;
}
