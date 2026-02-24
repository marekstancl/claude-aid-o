# Analysis Merge — Multi-Perspective Finding Consolidation

**Version:** 0.1.0
**Skill:** analysis-merge
**Dependencies:** parallel-dispatch, improvement-proposals

---

## TL;DR

When multiple analysis agents (security, backend, architect, etc.) review the same step,
their findings must be merged into a single actionable report. This skill defines three
merge strategies: **union** (keep everything), **consensus** (only confirmed findings),
and **weighted** (rank by domain expertise). The orchestrator selects the strategy from
the plan's `analysis_groups` entry, applies the corresponding algorithm, and produces
a structured `analysis_report` with action items and statistics.

---

## 1. Input Format (Analysis Agent Output)

Each analysis agent MUST produce this structure. Merge algorithms depend on consistent
field names and enum values.

```yaml
analysis_output:
  agent: "{role}"
  target_step: "step_{N}_{role}"
  mode: "review|audit|validation"
  findings:
    - severity: critical|high|medium|low|info
      category: "security|performance|architecture|correctness|style"
      location: "path/to/file:line"
      finding: "Description of what was found"
      recommendation: "What should be done"
      confidence: high|medium|low
  summary: "One-paragraph analysis summary"
  improvement_notes:       # Standard format from improvement-proposals.md
    - type: refactoring|performance|security|architecture|dx
      area: "path"
      observation: "..."
      suggestion: "..."
      priority: low|medium|high
```

### Validation Rules

| Rule | On Violation |
|------|-------------|
| Output MUST be valid YAML | Skip agent, log warning, proceed with others |
| `findings` array can be empty (`[]`) | Valid — agent found no issues |
| `severity` must be: critical, high, medium, low, info | Skip individual finding, log warning |
| `category` must be: security, performance, architecture, correctness, style | Skip individual finding, log warning |
| `confidence` must be: high, medium, low | Default to `medium` if missing |
| `agent` field must be non-empty | Skip agent entirely |
| `improvement_notes` follows `improvement-proposals.md` format | Process findings normally, skip invalid notes |

**Minimum viable input:** At least 2 valid agent outputs required for consensus/weighted.
If only 1 survives validation, fall back to union (passthrough).

---

## 2. Union Strategy

**Purpose:** Collect ALL findings from all perspectives. Nothing missed.

**When to use:** Security reviews, first-time analysis, maximum visibility needed.

### Algorithm

```
1. CONCATENATE all findings[] from all agents into a single list.

2. TAG each finding: finding.source_agent = analysis_output.agent

3. SORT by severity descending: critical → high → medium → low → info
   Within same severity: SORT by category alphabetically.

4. NO deduplication — same issue from 2 agents = 2 entries (both preserved).
   Rationale: seeing the same issue from multiple perspectives adds value.

5. MERGE improvement_notes from all agents:
   Concatenate + deduplicate per improvement-proposals.md (Section 3, Step 3).

6. BUILD merged_summary — concatenate agent summaries:
   "### {Agent Role} Perspective\n{summary}\n\n---\n\n"
```

### Example

Three agents analyze `step_3_backend`. Security finds 2 issues, backend finds 2 (one
overlapping with security), architect finds 1. **Union result:** 5 findings total. The
SQL injection appears twice (once from security, once from backend) — both preserved
with their respective `source_agent` tags.

---

## 3. Consensus Strategy

**Purpose:** Only keep findings confirmed by 2+ agents. High confidence, low noise.

**When to use:** Database validations, reducing false positives, large analysis groups (3+).

### Algorithm

```
1. COLLECT all findings from all agents. Tag each with source_agent.

2. COMPUTE similarity between every pair of findings from DIFFERENT agents:

   Similarity score (0.0 to 1.0):
   - Same file in location (exact path match):   +0.4
     OR same directory (path prefix match):       +0.2
   - Same category:                               +0.3
   - Same severity (exact):                       +0.2
     OR adjacent severity (±1 level):             +0.1
     Adjacent: critical↔high, high↔medium, medium↔low, low↔info
   - Description keyword overlap > 50%:           +0.1
     (Jaccard similarity of word sets from finding text)

   Threshold: similarity >= 0.6 = "consensus match"

3. GROUP findings:
   - "consensus": similarity >= 0.6 to at least 1 finding from DIFFERENT agent
   - "minority": no match above threshold

4. For each CONSENSUS group:
   a. Take most detailed finding (longest text) as primary description
   b. Record: agreed_by: [list of agent roles]
   c. ELEVATE to highest severity in the group
   d. ELEVATE to highest confidence in the group
   e. Merge recommendations (deduplicate, keep unique)
   f. Use most specific location (longest path with line number)

5. For each MINORITY finding:
   a. Keep in separate minority_findings section
   b. Tag: note: "Only one perspective reported this"
   c. Do NOT discard — may still be valid

6. BUILD merged_summary:
   "Analysis confirmed {N} issues across {M} perspectives.
    {count by severity}. Key consensus: {top 3 findings}."

7. COMPUTE: consensus_rate = consensus_groups / (consensus_groups + minority) * 100
```

### Example

Security reports critical SQL injection at `src/auth/login.py:42`, backend reports
high-severity SQL issue at same location. Similarity: same file (+0.4) + same category
(+0.3) + adjacent severity (+0.1) + keyword overlap (+0.1) = **0.9** (consensus match).
Result: merged to critical severity, `agreed_by: ["security", "backend"]`, both
recommendations combined.

---

## 4. Weighted Strategy

**Purpose:** Weight findings by agent domain expertise. Expert findings rank higher.

**When to use:** Architecture reviews, mixed-expertise groups, prioritized results needed.

### Default Weight Table

| Finding category | Primary expert (1.0) | Secondary (0.7) | Others (0.4) |
|------------------|----------------------|------------------|---------------|
| security         | security             | backend          | *             |
| performance      | backend, frontend    | observability    | *             |
| architecture     | architect            | domain           | *             |
| correctness      | qa                   | backend, frontend| *             |
| style            | docs-writer          | frontend         | *             |

### Severity Numeric Mapping

| Severity | Value |
|----------|-------|
| critical | 4.0   |
| high     | 3.0   |
| medium   | 2.0   |
| low      | 1.0   |
| info     | 0.5   |

### Algorithm

```
1. COLLECT all findings from all agents. Tag each with source_agent.

2. For EACH finding:
   a. Look up source agent's weight for finding.category (table above)
   b. Compute: weighted_severity = severity_numeric * weight

   Examples:
   - Security agent, HIGH security:   3.0 * 1.0 = 3.0
   - Frontend agent, HIGH security:   3.0 * 0.4 = 1.2
   - Backend agent, MEDIUM performance: 2.0 * 1.0 = 2.0

3. SORT by weighted_severity descending.
   Ties: raw severity descending, then weight descending.

4. DEDUPLICATE: same location AND same category →
   a. Keep higher weighted_severity
   b. Annotate: also_reported_by: ["{other_agents}"]

5. BUILD merged_summary:
   "Weighted analysis prioritized {N} findings.
    Top issues by domain expertise: {top 3 by weighted_severity}."
```

### Example

Security agent and frontend agent both report high-severity SQL injection at
`src/auth/login.py:42`. Security: `3.0 * 1.0 = 3.0`, frontend: `3.0 * 0.4 = 1.2`.
Security agent's finding kept, frontend listed in `also_reported_by`.

---

## 5. Analysis Report Format (Output)

Strategy-specific sections are present only when that strategy is active.

```yaml
analysis_report:
  id: "analysis_{N}_{purpose}"
  target_step: "step_{M}_{role}"
  mode: "review|audit|validation"
  merge_strategy: "union|consensus|weighted"
  perspectives: 3
  agents: ["security", "backend", "architect"]
  timestamp: "{ISO 8601}"

  # === UNION (present when merge_strategy = "union") ===
  findings:
    - source_agent: "security"
      severity: critical
      category: security
      location: "src/auth/login.py:42"
      finding: "SQL injection via unsanitized user input"
      recommendation: "Use parameterized queries"
      confidence: high

  # === CONSENSUS (present when merge_strategy = "consensus") ===
  consensus_items:
    - finding: "SQL injection risk in login"
      agreed_by: ["security", "backend"]
      severity: critical
      category: security
      location: "src/auth/login.py:42"
      merged_recommendation: "Use parameterized queries. Verify all input sanitization."
      confidence: high
  minority_findings:
    - source_agent: "architect"
      severity: medium
      category: architecture
      finding: "Controller structure could be simplified"
      note: "Only one perspective reported this"
  consensus_rate: "67%"

  # === WEIGHTED (present when merge_strategy = "weighted") ===
  weighted_findings:
    - finding: "SQL injection via unsanitized input"
      agent: "security"
      category: security
      base_severity: high
      weight: 1.0
      weighted_severity: 3.0
      location: "src/auth/login.py:42"
      recommendation: "Use parameterized queries"
      also_reported_by: ["backend"]

  # === ALWAYS present (all strategies) ===
  merged_summary: "Executive summary combining all perspectives..."

  action_items:
    - priority: critical
      action: "Fix SQL injection in login endpoint"
      assigned_to: "backend"
      source_findings: ["finding from security", "finding from backend"]
    - priority: high
      action: "Add input validation middleware"
      assigned_to: "backend"
      source_findings: ["finding from security"]

  improvement_notes: [...]    # Merged from all agents per improvement-proposals.md

  statistics:
    total_findings: 7
    by_severity: { critical: 1, high: 2, medium: 3, low: 1, info: 0 }
    by_category: { security: 3, performance: 1, architecture: 2, correctness: 1, style: 0 }
    by_agent: { security: 3, backend: 2, architect: 2 }
    consensus_rate: "67%"     # Only for consensus strategy, null otherwise
```

### Action Items Generation

```
1. Group findings by location (same file or module).
2. For each group, create one action item:
   a. priority = highest severity in the group
   b. action = concise imperative sentence describing the fix
   c. assigned_to = role best suited to fix:
      security findings → backend (code owner)
      performance → backend or frontend (path owner)
      architecture → architect (design) or backend (implementation)
      correctness → qa (test) or backend/frontend (fix)
      style → docs-writer or frontend
   d. source_findings = list of finding descriptions leading to this action
3. Sort by priority: critical → high → medium → low → info.
4. Limit to top 10 (if more, note "... and {N} more" in summary).
```

---

## 6. Orchestrator Integration

### Complete Flow: Dispatch to Evidence Storage

```
Step X completes → PHASE_CHECK pass → NEXT_PHASE
  │
  ├── Check plan.analysis_groups targeting step X
  │   └── If none → skip, proceed normally
  │
  ├── For each matching analysis_group:
  │   │
  │   ├── 1. DISPATCH analysis agents (per parallel-dispatch.md protocol)
  │   │      All agents in parallel (single message, multiple Task calls)
  │   │      Each receives: step X outputs, analysis mode, playbook, output format
  │   │
  │   ├── 2. COLLECT outputs
  │   │      Validate each analysis_output YAML (Section 1 rules)
  │   │      Skip invalid (log warning). Min 2 for consensus/weighted, else union.
  │   │
  │   ├── 3. MERGE findings (strategy from plan.analysis_groups entry)
  │   │      → union: Section 2  → consensus: Section 3  → weighted: Section 4
  │   │
  │   ├── 4. GENERATE analysis_report (Section 5 format)
  │   │
  │   ├── 5. SAVE evidence:
  │   │      evidence/{epic_id}/{run_id}/steps/step_{target}_{role}/
  │   │        analysis_{N}_{purpose}_raw_{agent}.yaml   # Each agent's raw output
  │   │        analysis_{N}_{purpose}_report.yaml        # Merged report
  │   │
  │   ├── 6. EVALUATE criticality:
  │   │      - Any critical findings → ESCALATION
  │   │        "Analysis found {N} critical issues in step {X}. PM must acknowledge."
  │   │      - Any high findings → log warning, notify PM (non-blocking)
  │   │      - Medium/low/info → proceed normally
  │   │
  │   └── 7. COLLECT improvement_notes from analysis
  │          Merge into step's improvement_notes (for Curator later)
  │
  └── Continue to next step (EXECUTING → NEXT_PHASE cycle)
```

### Evidence Directory Structure

```
evidence/{epic_id}/{run_id}/steps/step_{target}_{role}/
  analysis_1_security_review_raw_security.yaml
  analysis_1_security_review_raw_backend.yaml
  analysis_1_security_review_raw_architect.yaml
  analysis_1_security_review_report.yaml
  analysis_2_architecture_audit_raw_architect.yaml
  analysis_2_architecture_audit_raw_domain.yaml
  analysis_2_architecture_audit_report.yaml
```

### Curator Integration

```
analysis_report.improvement_notes
  → Stored in evidence alongside step's improvement_notes
  → Curator (post-run) reads ALL improvement_notes including from analysis
  → Deduplication applies normally (per improvement-proposals.md Section 3)
  → High-priority analysis notes may generate IMP-{NNN} proposals
```

### Stage Log Entries

Each analysis phase appends to `stage_log.jsonl`:

```json
{"timestamp": "...", "state": "ANALYSIS", "step": "step_3_backend", "action": "dispatch_analysis", "details": "Dispatching 3 agents: security, backend, architect"}
{"timestamp": "...", "state": "ANALYSIS", "step": "step_3_backend", "action": "collect_outputs", "details": "3/3 valid outputs collected"}
{"timestamp": "...", "state": "ANALYSIS", "step": "step_3_backend", "action": "merge_findings", "details": "consensus strategy: 4 consensus, 1 minority, rate=80%"}
{"timestamp": "...", "state": "ANALYSIS", "step": "step_3_backend", "action": "criticality_check", "details": "1 critical finding → ESCALATION"}
```

---

## 7. Strategy Selection Guide

### Quick Reference

| Situation | Strategy | Rationale |
|-----------|----------|-----------|
| Security review of auth code | union | Miss nothing — all security findings matter |
| DB migration validation | consensus | Only confirmed issues = high confidence |
| Architecture review of complex refactor | weighted | Architect's opinion weighs most |
| First review of new feature | union | Comprehensive coverage for unknown code |
| Pre-release audit | consensus | Reduce noise, focus on agreed-upon issues |
| Cross-cutting concern (logging, errors) | weighted | Domain expert's findings ranked higher |
| Small team (2 agents) | union | Not enough perspectives for consensus |
| Large team (4+ agents) | consensus | More agents = more noise, consensus filters |
| Performance-critical path | weighted | Backend/frontend experts prioritized |

### Decision Flowchart

```
Is this a security-sensitive review?
  YES → union (miss nothing)
  NO  ↓
Are there 3+ analysis agents?
  NO  → union (not enough for consensus)
  YES ↓
Is there a clear domain expert whose opinion should dominate?
  YES → weighted
  NO  ↓
Is reducing false positives the priority?
  YES → consensus
  NO  → union
```

**Default if unsure:** `union` (safest — nothing is lost).

The planner (`skills/planner.md`) auto-selects strategy based on `analysis_groups`
configuration. PM can override during PLAN_REVIEW.

---

## Reference Files

| File | Relevance |
|------|-----------|
| `skills/parallel-dispatch.md` | Dispatch protocol for analysis agents |
| `skills/improvement-proposals.md` | `improvement_notes` format (reused in input and output) |
| `skills/planner.md` | `analysis_groups` generation and auto-trigger rules |
| `defaults/templates/plan.schema.json` | `analysis_groups` schema definition |
| `skills/epic-orchestration.md` | Controller state machine (PHASE_CHECK triggers analysis) |
| `skills/gates-engine.md` | Quality gates (runs after analysis, separate concern) |

---

**Version:** 0.1.0
**Last Updated:** 2026-02-17
