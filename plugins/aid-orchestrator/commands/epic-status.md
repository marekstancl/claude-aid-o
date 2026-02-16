Show the current status of an EPIC pipeline — steps progress, gate results, budget, and evidence location.

## Usage

```
/epic-status [epic-id]
/epic-status                    # show all active EPICs
```

**Examples:**
```
/epic-status TEST-0001
/epic-status E-20260216-c2d1
/epic-status                    # overview of all
```

## Flow

### With epic-id: Detailed Status

1. **Find evidence:**
   - Look in `.aid-o/04-engine/evidence/{epic_id}/`
   - Find the latest `run_id` (most recent subdirectory)
   - Load `plan_progress.json`
   - Load `plan.json`
   - Load `gates_report.json` (if exists)
   - Load `stage_log.jsonl` (last 10 entries for recent activity)

2. **Find EPIC file:**
   - Search `.aid-o/02-epics/` for file matching epic_id
   - Extract title from EPIC's `# ` heading

3. **Display detailed status:**
   ```
   EPIC Status: {epic_id} — {title}
   ====================================
   State: {current state from plan_progress.json}
   Run: {run_id}
   Started: {started_at}

   Steps ({done_count}/{total_count}):
     ✅ step_1_architect — {objective} (done)
     ✅ step_2_domain — {objective} (done)
     🔄 step_3_backend — {objective} (running)
     ⏳ step_4_frontend — {objective} (pending) ← parallel with step 3
     ⏳ step_5_qa — {objective} (pending)
     ⏳ step_6_security — {objective} (pending)
     ⏳ step_7_docs — {objective} (pending)

   Gates: {status}
     {If gates have run:}
     ✅ tests_pass (attempt 1)
     ✅ lint_pass (attempt 1)
     ❌ security_scan_pass (attempt 2/3 — retrying)
     ⏳ docs_updated (not yet run)
     {If gates not yet run:}
     Not yet run (waiting for all steps to complete)

   Escalations: {count}
     {If any:}
     - Gate failure: security_scan_pass (PM decided: fix)

   Budget: ${spent_estimate} / ${max} ({percentage}%)

   Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

   Recent activity (last 5):
     10:05 PHASE_CHECK step_2_domain — pass
     10:03 EXECUTING step_2_domain — dispatch_agent
     10:01 NEXT_PHASE step_1_architect — done
     09:58 PHASE_CHECK step_1_architect — pass
     09:55 EXECUTING step_1_architect — dispatch_agent
   ```

**Status icons:**
- ✅ = done / pass
- 🔄 = running / in progress
- ⏳ = pending / not yet run
- ❌ = failed
- ⏭️ = skipped

### Without epic-id: Overview of All EPICs

1. **Scan for active EPICs:**
   - List files in `.aid-o/02-epics/` (not `archive/`)
   - For each, check if evidence exists in `.aid-o/04-engine/evidence/`

2. **Scan for completed EPICs:**
   - List files in `.aid-o/02-epics/archive/`
   - Show last 5

3. **Display overview:**
   ```
   Active EPICs
   ====================================
   1. TEST-0001 — Add Health Check Endpoint    [EXECUTING] step 3/7
   2. AUTH-0001 — User Authentication           [GATES] retry 2/3

   Recently Completed:
   3. FIX-0039 — Fix login timeout              [DONE] 2026-02-14

   No plan yet:
   4. PERF-0002 — Optimize queries              (run /plan-epic to start)

   Use /epic-status <epic-id> for details.
   ```

### Edge Cases

**No EPICs found:**
```
No EPICs found.

To get started:
1. Create an EPIC: .aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md
   Template: .aid-o/03-config/templates/epic.md
2. Generate plan: /plan-epic <path-to-epic>
3. Run: /run-epic
```

**EPIC exists but no plan:**
```
EPIC: {epic_id} — {title}
Status: No plan generated

Run /plan-epic {path} to create an execution plan.
```

**EPIC exists but no evidence (plan was generated but no run started):**
```
EPIC: {epic_id} — {title}
Status: Plan ready, not started

Plan: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
Steps: {count} | Roles: {list} | Budget: ${max}

Run /run-epic {epic_id} to start execution.
```

## Reference Files

- `skills/epic-orchestration.md` — Evidence store structure, plan_progress.json format
- `.aid-o/04-engine/evidence/` — where all run data lives

## Important

- This is a **read-only** command — it never modifies files
- If evidence directory doesn't exist, check `.aid-o/02-epics/` for the EPIC file and report "no run started"
- Budget estimation is approximate (based on prompt sizes and number of dispatches)
- Recent activity comes from `stage_log.jsonl` — show last 5-10 entries
