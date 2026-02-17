---
id: S-20260217-d9c4
type: new-feature
status: completed
priority: high
started: 2026-02-17
epic_id: ADO-0001
epic_session: 6
epic_file: workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md
plan_ref: workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md
ai_agent: Claude Opus 4.6
branch: session/S-20260217-d9c4-slack-autonomous-run
previous_session: workspace/sessions/active/S-20260217-1ffa-planner-parallelization.md
---

# Session 6: Slack + Autonomní Běh

## Objective

Implementovat Slack MCP integration skill pro asynchronní komunikaci s PM a Epic Queue
pro automatický pickup dalšího EPICu. Po této session bude Orchestrátor plně autonomní —
všechny PM touchpoints (plan review, escalation, merge approval, curator proposals,
audit summaries) půjdou přes Slack, a po dokončení EPICu se automaticky spustí další
z fronty.

Na konci session musí:
- `skills/slack-mcp.md` definovat kompletní Slack MCP integration protocol (7 message typů, formatting, response parsing, timeouts)
- Všechny PM touchpoints v `run-epic.md` (PLAN_REVIEW, ESCALATION, PM_APPROVAL) používat Slack MCP
- Curator proposals a rejection info jít přes Slack
- Auditor audit summaries jít přes Slack
- `skills/epic-queue.md` definovat queue management protocol (add, remove, prioritize, auto-pickup)
- `commands/epic-queue.md` poskytnout CLI interface pro správu fronty
- `epic-orchestration.md` DONE state spouštět auto-pickup dalšího EPICu z queue
- Fallback na chat-based komunikaci pokud Slack MCP není nakonfigurován
- `plugin.json` registrovat 2 nové skills + 1 nový command

## Context / Prerekvizity

Session 1 dodala:
- Plugin scaffold, `defaults/playbooks/` (9 playbooks)
- `defaults/policies/decision-policies.yaml` — auto_decisions, escalation_triggers

Session 2 dodala:
- `commands/run-epic.md` — state machine loop s PLAN_REVIEW, ESCALATION, PM_APPROVAL stavy (chat-based)
- `commands/epic-status.md` — zobrazení stavu pipeline

Session 3 dodala:
- `skills/gates-engine.md`, `skills/retry-engine.md` — gates + retry s escalation flow
- `agents/gate-fixer.md`

Session 4 dodala:
- `agents/curator.md` — post-session specialist (collect → dedup → propose → Orchestrátor → PM)
- `agents/auditor.md` — post-Epic specialist (5 audit typů → report → Orchestrátor → PM)
- `skills/improvement-proposals.md` — improvement_notes standard format

Session 5 dodala:
- `skills/planner.md` — dependency graph, parallel groups, analysis_groups
- `skills/parallel-dispatch.md` — paralelní dispatch protocol + branch management
- `skills/analysis-merge.md` — multi-perspective merge strategie

**Aktuální stav PM komunikace (chat-based):**
- `run-epic.md` PLAN_REVIEW → "Present plan to PM, wait for GO/REVISE/ABORT"
- `run-epic.md` ESCALATION → "Present failure to PM, wait for Fix/Skip/Abort"
- `run-epic.md` PM_APPROVAL → "Present summary to PM, wait for APPROVE/REJECT/REVISE"
- `agents/curator.md` → "Orchestrátor → PM (Slack v Session 6, chat nyní)"
- `agents/auditor.md` → "Summary → PM (chat nyní, Slack v Session 6)"
- `skills/epic-orchestration.md` DONE → Curator+Auditor dispatched, proposals → PM

**Klíčový design (z WORKFLOWS.md WF-13):**
- 7 message typů: Escalation, Plan Approval, Merge Approval, Proposal, Rejection Info, Audit Summary, Status Update
- 3 senders: Orchestrator, Curator (via Orch.), Auditor (via Orch.)
- Princip: "Everything that goes to PM goes through Slack. Even rejections = info."

## Deliverables

- [x] `skills/slack-mcp.md` — Slack MCP integration skill
- [x] Update `commands/run-epic.md` — PLAN_REVIEW, ESCALATION, PM_APPROVAL → Slack
- [x] Update `skills/epic-orchestration.md` — State definitions pro Slack + DONE auto-pickup
- [x] Update `agents/curator.md` — Slack integration pro proposals + info
- [x] Update `agents/auditor.md` — Slack integration pro summaries
- [x] `skills/epic-queue.md` — Epic Queue management skill
- [x] `commands/epic-queue.md` — `/epic-queue` command
- [x] Update `commands/aid-help.md` — Slack + Epic Queue dokumentace
- [x] Update `plugin.json` — 2 nové skills + 1 nový command
- [x] Cross-reference verification

## Phases

### Phase 1: Slack MCP Skill — `skills/slack-mcp.md`

**Cíl:** Definovat kompletní Slack MCP integration protocol — jak Orchestrátor (a přes něj Curator/Auditor) komunikuje s PM přes Slack. Skill neimplementuje MCP server samotný (ten je externí), ale definuje **protocol, message formats, response parsing a timeouts** pro AID plugin.

**Skill musí definovat:**

1. **MCP Server Interface (co AID očekává od Slack MCP):**
   ```
   Slack MCP server musí poskytnout 3 tools:

   slack_send_message(channel, message_type, payload)
     → Pošle formátovanou zprávu do Slack kanálu
     → Vrátí message_id pro tracking

   slack_wait_for_reply(message_id, timeout_minutes, reminder_interval_minutes)
     → Čeká na PM odpověď (thread reply nebo reaction)
     → timeout s konfigurací (default 1440 min = 24h)
     → Pošle reminder po reminder_interval (default 60 min)
     → Vrátí { response_type, response_value, responder, timestamp }

   slack_update_message(message_id, updated_payload)
     → Aktualizuje existující zprávu (např. po PM rozhodnutí)
   ```

2. **7 Message Typů (z WF-13) — formát a obsah:**

   **A) Escalation (expects reply):**
   ```
   Sender: Orchestrator
   When: Gate failure after max retries, agent error, scope violation, budget exceeded
   Format:
     🚨 ESCALATION — {trigger_reason}
     ━━━━━━━━━━━━━━━━
     EPIC: {epic_id} — {epic_title}
     State: {current_state}

     📋 Details:
     {failure_details — max 500 chars}

     🎯 Options:
     ✅ A) {fix option from decision-policies.yaml}
     ⏭️ B) {skip option}
     🛑 C) Abort EPIC

     💡 Recommendation: {auto recommendation}

     Reply with A, B, or C (or thread for discussion)

   PM Response parsing:
     "A" | "fix" | "retry" → return { response_type: "fix", ... }
     "B" | "skip" → return { response_type: "skip", ... }
     "C" | "abort" → return { response_type: "abort", ... }
     Thread reply with text → return { response_type: "discussion", message: "..." }
   ```

   **B) Plan Approval (expects reply):**
   ```
   Sender: Orchestrator
   When: PLAN_REVIEW state — Plan JSON generated, needs PM approval
   Format:
     📋 PLAN REVIEW — {epic_title}
     ━━━━━━━━━━━━━━━━
     EPIC: {epic_id}
     Steps: {total_steps} ({parallel_groups} parallel groups, {analysis_groups} analysis groups)
     Estimated agents: {agent_list}

     📊 Plan Summary:
     {step_summary_table — max 20 lines}

     ⚙️ Full plan: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json

     Reply: GO / REVISE / ABORT

   PM Response parsing:
     "GO" | "go" | "approve" | ✅ reaction → { response_type: "go" }
     "REVISE" + text → { response_type: "revise", feedback: "..." }
     "ABORT" | "abort" | ❌ reaction → { response_type: "abort" }
   ```

   **C) Merge Approval (expects reply):**
   ```
   Sender: Orchestrator
   When: PM_APPROVAL state — all gates pass, ready for merge
   Format:
     ✅ EPIC COMPLETE — Ready for Merge
     ━━━━━━━━━━━━━━━━
     EPIC: {epic_id} — {epic_title}
     Steps: {completed}/{total} completed
     Gates: ALL PASS ✅

     📊 Changes:
     • {file_count} files changed
     • {commit_count} commits
     • Branches: {branch_list}

     📁 Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

     Reply: APPROVE / REJECT / REVISE

   PM Response parsing:
     "APPROVE" | "approve" | ✅ reaction → { response_type: "approve" }
     "REJECT" + text → { response_type: "reject", feedback: "..." }
     "REVISE" + text → { response_type: "revise", feedback: "..." }
   ```

   **D) Improvement Proposal (expects reply):**
   ```
   Sender: Curator (via Orchestrator)
   When: Curator generates proposals, Orchestrator approves → forward to PM
   Format:
     💡 IMPROVEMENT PROPOSAL — {proposal_title}
     ━━━━━━━━━━━━━━━━
     ID: {IMP-NNN}
     Type: {refactoring|performance|security|architecture|dx}
     Area: {area}
     Priority: {priority}
     Sources: {agent_list} ({source_count} agents noticed this)

     📋 Observation:
     {observation}

     🎯 Proposed Action:
     {proposed_action}

     ⏱️ Estimated Effort: {small|medium|large}

     Reply: APPROVE / DEFER / REJECT

   PM Response parsing:
     "APPROVE" | "approve" → { response_type: "approve" }
     "DEFER" + optional reason → { response_type: "defer", reason: "..." }
     "REJECT" + optional reason → { response_type: "reject", reason: "..." }
   ```

   **E) Rejection Info (no reply expected):**
   ```
   Sender: Orchestrator / Curator
   When: Orchestrator rejects a Curator proposal (info only)
   Format:
     ℹ️ PROPOSAL REJECTED by Orchestrator
     ━━━━━━━━━━━━━━━━
     ID: {IMP-NNN}
     Reason: {rejection_reason}
     Status: Logged to backlog.md (status: orchestrator-rejected)
   ```

   **F) Audit Summary (no reply expected):**
   ```
   Sender: Auditor (via Orchestrator)
   When: Post-EPIC audit completes
   Format:
     📊 AUDIT SUMMARY — {epic_id}
     ━━━━━━━━━━━━━━━━
     Overall Score: {score}/100 ({trend_arrow} {delta} from previous)

     📈 Scores:
     • Code Quality: {score}/100
     • Security: {score}/100
     • Documentation: {score}/100
     • Frontend: {score}/100 (or N/A)
     • Database: {score}/100 (or N/A)

     🔴 Critical Findings: {count}
     🟡 Warnings: {count}
     🟢 Suggestions: {count}

     📁 Full report: .aid-o/04-engine/evidence/{epic_id}/audit-report.md

     {top_3_findings_if_critical}
   ```

   **G) Status Update (no reply expected):**
   ```
   Sender: Orchestrator
   When: EPIC starts, phase completes, EPIC ends (informational)
   Format:
     📌 STATUS — {epic_id}
     {status_message}

     Examples:
     "🚀 EPIC started — 8 steps planned"
     "✅ Phase 3/8 complete — backend.md done (12 files changed)"
     "🏁 EPIC completed — merged to main"
     "⏸️ EPIC paused — waiting for PM decision"
   ```

3. **Configuration (co PM nastaví):**
   ```yaml
   # .aid-o/03-config/policies/slack-config.yaml
   slack:
     enabled: true                          # false = fallback na chat
     channel: "#aid-orchestrator"           # Slack channel pro AID zprávy
     pm_user_id: "U1234567"                # PM's Slack user ID (pro mentions)

     timeouts:
       plan_approval_minutes: 1440          # 24h default
       escalation_minutes: 480              # 8h default
       merge_approval_minutes: 1440         # 24h
       proposal_minutes: 4320              # 72h (lower priority)

     reminders:
       enabled: true
       interval_minutes: 60                 # Reminder every hour
       max_reminders: 3                     # Max 3 reminders before timeout action

     timeout_actions:
       plan_approval: "wait"                # wait|abort
       escalation: "wait"                   # wait|skip|abort
       merge_approval: "wait"               # wait|abort
       proposal: "defer"                    # defer|wait
   ```

4. **Fallback Protocol (Slack nedostupný / nekonfigurovaný):**
   ```
   IF .aid-o/03-config/policies/slack-config.yaml neexistuje OR slack.enabled = false:
     → Fallback na chat-based komunikaci (stávající chování)
     → Log: "Slack MCP not configured, using chat fallback"

   IF Slack MCP server není dostupný (tool call fails):
     → Retry 3x s exponential backoff (1s, 5s, 15s)
     → Po 3 failures: fallback na chat + warning log
     → Pokračuj v EPIC execution (nesmí blokovat kvůli Slack outage)
   ```

5. **Evidence (Slack messages logging):**
   ```
   Každý Slack message se loguje do:
   .aid-o/04-engine/evidence/{epic_id}/{run_id}/slack_log.jsonl

   Format:
   {"ts": "ISO8601", "type": "escalation", "message_id": "slack_msg_id", "channel": "#aid", "status": "sent"}
   {"ts": "ISO8601", "type": "escalation", "message_id": "slack_msg_id", "response": "fix", "responder": "PM", "latency_min": 42}
   ```

**Reference soubory:**
- `workspace/workflow/plans/WORKFLOWS.md` WF-13 — Slack Integration workflow
- `commands/run-epic.md` — PLAN_REVIEW, ESCALATION, PM_APPROVAL (current chat-based)
- `skills/epic-orchestration.md` — State definitions (ESCALATION, PM_APPROVAL)
- `agents/curator.md` — Curator → Orchestrátor → PM flow
- `agents/auditor.md` — Auditor → Orchestrátor → PM flow
- `defaults/policies/decision-policies.yaml` — escalation_triggers, auto_decisions

**Acceptance:**
- [x]7 message typů kompletně specifikováno (formát + response parsing)
- [x]MCP server interface definováno (3 tools: send, wait, update)
- [x]Slack config format definován (`slack-config.yaml`)
- [x]Fallback protocol pro nedostupný/nekonfigurovaný Slack
- [x]Evidence logging (slack_log.jsonl)
- [x]Timeout handling s reminders a configurable timeout actions

---

### Phase 2: Run-Epic Slack Integration — `commands/run-epic.md`

**Cíl:** Přepojit 3 PM touchpoints v run-epic.md z chat-based na Slack MCP.

**Změny v run-epic.md:**

1. **PLAN_REVIEW state (cca řádky 70-120):**
   ```
   BEFORE (chat):
     "Present plan to PM. Wait for GO/REVISE/ABORT."

   AFTER (Slack):
     1. Resolve communication channel:
        - Read .aid-o/03-config/policies/slack-config.yaml
        - IF slack.enabled → use Slack MCP (per skills/slack-mcp.md)
        - ELSE → fallback na chat (stávající chování)
     2. IF Slack:
        - Format Plan Approval message (type B from slack-mcp.md)
        - Call slack_send_message(channel, "plan_approval", payload)
        - Call slack_wait_for_reply(message_id, timeout, reminder_interval)
        - Parse response → GO/REVISE/ABORT
        - Log to slack_log.jsonl
     3. Save pm_plan_approval.json (same as before)
     4. Transition based on response
   ```

2. **ESCALATION state (cca řádky 336-410):**
   ```
   BEFORE (chat):
     "Present failure context to PM with options."

   AFTER (Slack):
     1. Resolve communication channel (same logic)
     2. IF Slack:
        - Format Escalation message (type A from slack-mcp.md)
        - Call slack_send_message(channel, "escalation", payload)
        - Call slack_wait_for_reply(message_id, timeout, reminder_interval)
        - Parse response → fix/skip/abort
        - IF response_type = "discussion" → include PM's thread text as context
        - Log to slack_log.jsonl
     3. Save pm_decision.json (same as before)
     4. Execute PM's choice
   ```

3. **PM_APPROVAL state (cca řádky 425-465):**
   ```
   BEFORE (chat):
     "Present final summary to PM. Wait for APPROVE/REJECT/REVISE."

   AFTER (Slack):
     1. Resolve communication channel
     2. IF Slack:
        - Format Merge Approval message (type C from slack-mcp.md)
        - Call slack_send_message(channel, "merge_approval", payload)
        - Call slack_wait_for_reply(message_id, timeout, reminder_interval)
        - Parse response → approve/reject/revise
        - Log to slack_log.jsonl
     3. Save pm_decision.json
     4. Transition
   ```

4. **Status Updates (informational — nové):**
   ```
   Přidat na klíčových místech:
   - IDLE → PLANNING: "🚀 EPIC started — generating plan..."
   - EXECUTING (each step start): "⚡ Step {N}/{total}: {role} started"
   - NEXT_PHASE → GATES: "🔍 All steps complete — running gates..."
   - DONE: "🏁 EPIC completed — merged to main"

   Status updates = no reply expected, fire-and-forget.
   IF Slack fails for status → silently skip (non-critical).
   ```

5. **Helper function (na začátek run-epic.md):**
   ```
   ## PM Communication Protocol

   All PM communication follows `skills/slack-mcp.md`.

   resolve_pm_channel():
     1. Read .aid-o/03-config/policies/slack-config.yaml
     2. IF file exists AND slack.enabled = true → return "slack"
     3. ELSE → return "chat"

   send_pm_message(type, payload):
     channel = resolve_pm_channel()
     IF channel = "slack":
       message_id = slack_send_message(config.channel, type, payload)
       return { channel: "slack", message_id }
     ELSE:
       Present message in chat (existing format)
       return { channel: "chat" }

   wait_pm_response(message_ref, timeout_type):
     IF message_ref.channel = "slack":
       timeout = config.timeouts[timeout_type]
       reminder = config.reminders.interval_minutes
       response = slack_wait_for_reply(message_ref.message_id, timeout, reminder)
       IF response.timeout:
         action = config.timeout_actions[timeout_type]
         return { response_type: action, auto: true, reason: "timeout" }
       return response
     ELSE:
       Wait for chat response (existing behavior)
   ```

**Reference soubory:**
- `skills/slack-mcp.md` (Phase 1) — message types, formats, parsing
- `commands/run-epic.md` — current implementation
- `skills/epic-orchestration.md` — state definitions

**Acceptance:**
- [x]PLAN_REVIEW → Slack MCP (Plan Approval message) s fallback na chat
- [x]ESCALATION → Slack MCP (Escalation message) s fallback na chat
- [x]PM_APPROVAL → Slack MCP (Merge Approval message) s fallback na chat
- [x]Status updates na klíčových bodech (EPIC start, step start, gates, done)
- [x]Helper function `resolve_pm_channel()` / `send_pm_message()` / `wait_pm_response()`
- [x]Timeout handling → configurable default action
- [x]Evidence: slack_log.jsonl + stávající pm_decision.json

---

### Phase 3: Epic-Orchestration Skill Update — `skills/epic-orchestration.md`

**Cíl:** Aktualizovat state definitions pro Slack komunikaci a přidat auto-pickup v DONE.

**Změny:**

1. **State 9: ESCALATION** — přidat Slack alternativu:
   ```
   Actions:
   1. Resolve PM communication channel (per skills/slack-mcp.md)
   2. IF Slack → Format Escalation message, send via MCP, wait for reply
      ELSE → Present in chat (existing)
   3. ... (rest same)
   ```

2. **State 10: PM_APPROVAL** — přidat Slack alternativu:
   ```
   Actions:
   1. Resolve PM communication channel
   2. IF Slack → Format Merge Approval message, send, wait
      ELSE → Present in chat
   3. ... (rest same)
   ```

3. **State 3: PLAN_REVIEW** — přidat Slack alternativu:
   ```
   Same pattern as above.
   ```

4. **State 11: DONE** — přidat auto-pickup:
   ```
   Rozšířit DONE state:

   After existing actions (merge, archive, Curator, Auditor)...

   4. EPIC QUEUE CHECK:
      a. Read Epic Queue (per skills/epic-queue.md)
      b. IF queue has next EPIC with status "queued":
         - Send Status Update via Slack: "🔄 Auto-starting next EPIC: {next_epic_id}"
         - Set next EPIC status to "running"
         - Transition: DONE → IDLE → PLANNING (with next EPIC)
      c. ELSE:
         - Send Status Update: "✅ All queued EPICs complete. Orchestrator idle."
         - Remain in IDLE
   ```

5. **Nový state diagram note:**
   ```
   Communication Protocol:
   - States PLAN_REVIEW, ESCALATION, PM_APPROVAL use skills/slack-mcp.md
   - Slack MCP is preferred. Chat fallback if Slack not configured.
   - Status updates are fire-and-forget (non-blocking)
   - Epic Queue enables DONE → IDLE loop for continuous execution
   ```

**Acceptance:**
- [x]ESCALATION, PM_APPROVAL, PLAN_REVIEW referencují `skills/slack-mcp.md`
- [x]Fallback na chat zmíněn ve všech touchpointech
- [x]DONE state má Epic Queue check s auto-pickup
- [x]State diagram note vysvětluje komunikační protokol

---

### Phase 4: Curator Slack Integration — `agents/curator.md`

**Cíl:** Aktualizovat Curator agenta, aby Orchestrátor → PM komunikace šla přes Slack.

**Změny v `agents/curator.md`:**

1. **Orchestrátor Integration section — update flow:**
   ```
   BEFORE:
     Orchestrátor → PM (Slack v Session 6, chat nyní)

   AFTER:
     Orchestrátor evaluuje proposals:
     ├── ZAMÍTNE → backlog.md (status: orchestrator-rejected)
     │     + Slack: Rejection Info message (type E — no reply expected)
     │     + Fallback: chat info
     └── SCHVÁLÍ → forward proposal to PM
           + Slack: Improvement Proposal message (type D — expects reply)
           + Fallback: chat with options
           PM decides:
           ├── PM SCHVÁLÍ → Orchestrátor creates new Epic
           ├── PM ODLOŽÍ → backlog.md (status: deferred)
           └── PM ZAMÍTNE → backlog.md (status: pm-rejected)
   ```

2. **Batch proposals handling:**
   ```
   Pokud Curator generuje více proposals:
   - Pošle každý jako separátní Slack message (ne jeden velký message)
   - PM odpovídá na každý zvlášť
   - Orchestrátor čeká na všechny odpovědi (parallel wait)
   - Timeout pro proposals je delší (72h default — lower priority)
   ```

3. **Reference na `skills/slack-mcp.md`** — přidat do References sekce

**Acceptance:**
- [x]Curator → Orchestrátor → Slack PM flow aktualizován
- [x]Rejection Info přes Slack (type E)
- [x]Proposals přes Slack (type D) s expects reply
- [x]Batch handling popsáno
- [x]Reference na slack-mcp.md

---

### Phase 5: Auditor Slack Integration — `agents/auditor.md`

**Cíl:** Aktualizovat Auditor agenta, aby audit summary šel přes Slack.

**Změny v `agents/auditor.md`:**

1. **Integration Flow section — update:**
   ```
   BEFORE:
     Summary → PM (chat nyní, Slack v Session 6)

   AFTER:
     → audit_report → evidence/{epic_id}/audit-report.md
     → findings → Orchestrátor validates
       ├── Orchestrátor schválí → Curator processes into backlog
       └── Orchestrátor zamítne → log + Slack Rejection Info (type E)
     → Summary → Slack Audit Summary (type F — no reply expected)
       + Pokud critical findings: mention PM user (@PM check this!)
       + Fallback: chat summary
   ```

2. **Critical findings escalation:**
   ```
   Pokud audit najde CRITICAL findings:
   - Audit Summary message includes prominent warning
   - Orchestrátor MAY escalate jako ESCALATION message (type A — expects reply)
     pokud finding matches escalation_triggers z decision-policies.yaml
   ```

3. **Reference na `skills/slack-mcp.md`**

**Acceptance:**
- [x]Auditor → Orchestrátor → Slack flow aktualizován
- [x]Audit Summary přes Slack (type F — no reply)
- [x]Critical findings escalation definován
- [x]Reference na slack-mcp.md

---

### Phase 6: Epic Queue Skill + Command

**Cíl:** Vytvořit Epic Queue systém pro autonomní běh — automatický pickup dalšího EPICu.

#### 6a. `skills/epic-queue.md` — Epic Queue Management Skill

**Skill musí definovat:**

1. **Queue Format:**
   ```yaml
   # .aid-o/04-engine/epic-queue.yaml
   queue:
     - epic_id: "E-20260217-a1b2-user-auth"
       path: ".aid-o/02-epics/E-20260217-a1b2-user-auth.md"
       priority: high
       status: running              # queued|running|completed|failed|paused
       added_at: "2026-02-17T10:00:00Z"
       started_at: "2026-02-17T10:05:00Z"
       completed_at: null

     - epic_id: "E-20260217-c3d4-api-v2"
       path: ".aid-o/02-epics/E-20260217-c3d4-api-v2.md"
       priority: medium
       status: queued
       added_at: "2026-02-17T10:01:00Z"
       started_at: null
       completed_at: null
   ```

2. **Queue Operations:**
   ```
   add(epic_path, priority) → Přidej EPIC do queue (status: queued)
   remove(epic_id) → Odstraň z queue (only if status = queued)
   next() → Vrať příští EPIC (highest priority + oldest, status = queued)
   start(epic_id) → Set status = running, started_at = now
   complete(epic_id, status) → Set status = completed|failed, completed_at = now
   pause() → Pozastav auto-pickup (global pause flag)
   resume() → Obnov auto-pickup
   list() → Vrať celou frontu se statusy
   reorder(epic_id, new_priority) → Změň prioritu
   ```

3. **Auto-Pickup Protocol:**
   ```
   Po DONE state v epic-orchestration.md:
   1. POST-PROCESSING dokončeno (Curator + Auditor)
   2. Read epic-queue.yaml
   3. IF queue.paused → STOP (log "Queue paused, skipping auto-pickup")
   4. next_epic = queue.next()
   5. IF next_epic exists:
      - queue.start(next_epic.epic_id)
      - Slack Status Update: "🔄 Auto-starting: {next_epic.epic_id}"
      - Start new run-epic loop with next_epic
   6. ELSE:
      - Slack Status Update: "✅ Queue empty. Orchestrator idle."
      - STOP
   ```

4. **Priority Rules:**
   ```
   Priority levels: critical > high > medium > low
   Within same priority: FIFO (oldest first)
   Running EPIC cannot be preempted (no priority inversion)
   ```

5. **Safety Guards:**
   ```
   - MAX concurrent EPICs = 1 (no parallel EPIC execution)
   - IF previous EPIC failed → pause queue + Slack Escalation to PM
   - IF PM does /epic-queue pause → stop auto-pickup immediately
   - Queue state persists in YAML file (survives session restarts)
   ```

#### 6b. `commands/epic-queue.md` — `/epic-queue` Command

**Command interface:**
```
/epic-queue                    # Zobraz frontu (= list)
/epic-queue list              # Zobraz frontu se statusy
/epic-queue add <epic-path> [--priority high|medium|low]
/epic-queue remove <epic-id>
/epic-queue next              # Zobraz příští EPIC v pořadí
/epic-queue pause             # Pozastav auto-pickup
/epic-queue resume            # Obnov auto-pickup
/epic-queue reorder <epic-id> --priority <new-priority>
```

**Display format (list):**
```
📋 EPIC Queue
━━━━━━━━━━━━━
🟢 RUNNING: E-20260217-a1b2-user-auth (high) — started 2h ago
⏳ QUEUED:  E-20260217-c3d4-api-v2 (medium) — added 1h ago
⏳ QUEUED:  E-20260218-e5f6-dashboard (low) — added 30m ago
✅ DONE:    E-20260216-g7h8-scaffold (high) — completed 3h ago

Auto-pickup: ✅ Active (2 EPICs queued)
```

**Reference soubory:**
- `skills/epic-orchestration.md` DONE state — auto-pickup trigger
- `commands/run-epic.md` — IDLE state (receives next EPIC from queue)

**Acceptance:**
- [x]`skills/epic-queue.md` definuje queue format, operations, auto-pickup protocol
- [x]`commands/epic-queue.md` implementuje CLI interface (list, add, remove, next, pause, resume, reorder)
- [x]Auto-pickup: DONE → check queue → start next EPIC (or idle)
- [x]Safety guards: max 1 concurrent, failed → pause, persists in YAML
- [x]Priority ordering: critical > high > medium > low, FIFO within same

---

### Phase 7: Plugin Integration + Cross-references

**Cíl:** Registrovat nové artefakty, aktualizovat dokumentaci, ověřit konzistenci.

**Úkoly:**

1. **Update `plugin.json`:**
   - Skills: +2 (`slack-mcp`, `epic-queue`) → 12 total
   - Commands: +1 (`epic-queue`) → 17 total
   - Agents: 18 (beze změny)
   - Přidat `defaults/policies/slack-config.yaml` do default files

2. **Update `commands/aid-help.md`:**
   - Přidat sekci "Slack Integration":
     - Jak nastavit Slack (slack-config.yaml)
     - Message typy a co PM uvidí
     - Timeout behavior
   - Přidat sekci "Epic Queue":
     - Jak přidávat EPICy do fronty
     - Auto-pickup behavior
     - Pause/resume
   - Update workflow overview (zmínit autonomous loop)

3. **Vytvořit `defaults/policies/slack-config.yaml`:**
   - Default konfigurace (slack.enabled: false — opt-in)
   - Komentáře vysvětlující každé pole
   - Všechny timeout defaults

4. **Cross-reference verification:**
   - `skills/slack-mcp.md` → referencován z run-epic.md, epic-orchestration.md, curator.md, auditor.md
   - `skills/epic-queue.md` → referencován z epic-orchestration.md DONE, commands/epic-queue.md
   - `commands/epic-queue.md` → referencován z aid-help.md, plugin.json
   - `defaults/policies/slack-config.yaml` → referencován z slack-mcp.md
   - Message typy konzistentní mezi slack-mcp.md a všemi sendery (7 typů)

**Acceptance:**
- [x]plugin.json registruje 18 agents, 17 commands, 12 skills
- [x]aid-help.md pokrývá Slack + Epic Queue
- [x]slack-config.yaml default existuje
- [x]Všechny cross-references validní (žádné broken links)

---

### Phase 8: Smoke Test

**Cíl:** Ověřit kompletnost a konzistenci všech deliverables.

**Test scénáře:**

1. **File existence:**
   - `skills/slack-mcp.md` existuje
   - `skills/epic-queue.md` existuje
   - `commands/epic-queue.md` existuje
   - `defaults/policies/slack-config.yaml` existuje

2. **Slack message types (7):**
   - slack-mcp.md definuje: Escalation, Plan Approval, Merge Approval, Proposal, Rejection Info, Audit Summary, Status Update
   - Každý typ má: format, sender, expects_reply flag, response parsing (pokud expects reply)

3. **Integration consistency:**
   - run-epic.md PLAN_REVIEW referencuje slack-mcp.md
   - run-epic.md ESCALATION referencuje slack-mcp.md
   - run-epic.md PM_APPROVAL referencuje slack-mcp.md
   - curator.md referencuje slack-mcp.md (Proposal + Rejection Info)
   - auditor.md referencuje slack-mcp.md (Audit Summary)
   - epic-orchestration.md DONE referencuje epic-queue.md

4. **Fallback:**
   - run-epic.md zmíňuje fallback na chat
   - slack-mcp.md definuje fallback protocol

5. **Epic Queue:**
   - epic-queue.md definuje YAML format + operations
   - commands/epic-queue.md implementuje CLI
   - epic-orchestration.md DONE má auto-pickup

6. **Plugin consistency:**
   - plugin.json counts: 18 agents, 17 commands, 12 skills
   - Každý registrovaný soubor existuje

7. **Cross-references:**
   - Všechny file paths v referencích existují
   - Message type names konzistentní

**Acceptance:**
- [x]4 nové soubory existují a nejsou prázdné
- [x]plugin.json aktualizováno
- [x]7 message typů konzistentně definováno
- [x]Fallback protocol definován
- [x]Auto-pickup flow kompletní
- [x]Cross-references bez broken links

---

## DoD Gates

- [x] `skills/slack-mcp.md` definuje 7 message typů s kompletní specifikací (formát, parsing, timeouts)
- [x] `run-epic.md` PLAN_REVIEW/ESCALATION/PM_APPROVAL používají Slack MCP s fallback na chat
- [x] `epic-orchestration.md` state definitions aktualizovány pro Slack + auto-pickup
- [x] Curator → Orchestrátor → Slack PM flow funguje (proposals + rejection info)
- [x] Auditor → Orchestrátor → Slack PM flow funguje (audit summaries)
- [x] `skills/epic-queue.md` definuje queue management + auto-pickup protocol
- [x] `commands/epic-queue.md` implementuje CLI (list, add, remove, next, pause, resume)
- [x] `defaults/policies/slack-config.yaml` existuje s defaults
- [x] Backward compatible: Slack disabled → chat fallback (stávající chování)
- [x] Timeout handling s reminders a configurable default actions
- [x] `plugin.json` registruje 18 agents, 17 commands, 12 skills
- [x] `aid-help.md` pokrývá Slack + Epic Queue
- [x] Cross-reference verification prošla

## Architectural Notes

### Communication Architecture (Before vs After)

```
BEFORE (Sessions 1-5): Chat-based, blocking
  Orchestrator → [chat] → PM → [chat] → Orchestrator
  - Synchronous — Orchestrator waits in conversation
  - PM must be in same chat session
  - No persistence — context lost if session ends

AFTER (Session 6): Slack-based, async
  Orchestrator → [Slack MCP] → Slack channel → PM reads when available
  PM → [Slack thread/reaction] → [Slack MCP] → Orchestrator
  - Asynchronous — PM responds when convenient
  - Persistent — messages stay in Slack
  - Reminders — Orchestrator reminds PM if no response
  - Timeout → configurable default action
```

### Epic Queue Architecture

```
.aid-o/04-engine/epic-queue.yaml (persistent state)
  │
  ├── /epic-queue add → adds EPIC (status: queued)
  ├── /epic-queue list → displays queue
  ├── /epic-queue pause → sets global pause flag
  │
  └── epic-orchestration.md DONE state:
        POST-PROCESSING complete
          → Read epic-queue.yaml
          → IF not paused AND next exists:
              → Auto-start next EPIC
          → ELSE:
              → Idle
```

### Data Flow: Full Autonomous Cycle

```
PM queues 3 EPICs via /epic-queue add
  │
  ├── EPIC 1: run-epic → PLANNING → PLAN_REVIEW (Slack) → PM says GO
  │     → EXECUTING (agents work) → GATES → PM_APPROVAL (Slack) → PM APPROVE
  │     → DONE: merge + Curator + Auditor → Slack summaries
  │     → Auto-pickup: EPIC 2 from queue
  │
  ├── EPIC 2: run-epic → ... → DONE
  │     → Auto-pickup: EPIC 3 from queue
  │
  └── EPIC 3: run-epic → ... → DONE
        → Queue empty → Slack: "All complete, idle"
```

### Files Changed/Created Summary

```
NEW files (4):
  skills/slack-mcp.md                    # Slack MCP integration protocol
  skills/epic-queue.md                   # Epic Queue management
  commands/epic-queue.md                 # /epic-queue CLI
  defaults/policies/slack-config.yaml    # Default Slack config

MODIFIED files (6):
  commands/run-epic.md                   # 3 states → Slack MCP
  skills/epic-orchestration.md           # States + DONE auto-pickup
  agents/curator.md                      # Slack proposals + rejection info
  agents/auditor.md                      # Slack audit summaries
  commands/aid-help.md                   # Slack + Queue docs
  plugin.json                            # New registrations
```

## Session Log

| Čas | Událost |
|-----|---------|
| 2026-02-17 | Session file vytvořen, 8 phases definováno |
| 2026-02-17 | Phase 1: `skills/slack-mcp.md` vytvořen (~511 řádků) — 7 message typů, 3 MCP tools, PM Communication Protocol, fallback, evidence logging |
| 2026-02-17 | Phase 2: `commands/run-epic.md` aktualizován — PLAN_REVIEW/ESCALATION/PM_APPROVAL → Slack MCP, DONE → POST-PROCESSING + Epic Queue, Status Updates section |
| 2026-02-17 | Phase 3: `skills/epic-orchestration.md` aktualizován — States 3/9/10/11 → Slack, Communication Protocol section, Configuration References |
| 2026-02-17 | Phase 4: `agents/curator.md` aktualizován — Slack Type D (Proposal) + Type E (Rejection Info), batch handling |
| 2026-02-17 | Phase 5: `agents/auditor.md` aktualizován — Slack Type F (Audit Summary), critical findings → Type A escalation |
| 2026-02-17 | Phase 6: `skills/epic-queue.md` (~237 řádků) + `commands/epic-queue.md` (~176 řádků) vytvořeny — queue format, operations, auto-pickup, CLI |
| 2026-02-17 | Phase 7: `plugin.json` aktualizován (18 agents, 17 commands, 12 skills), `defaults/policies/slack-config.yaml` vytvořen, `aid-help.md` rozšířen o Slack + Queue topics |
| 2026-02-17 | Phase 8: Smoke test — 54/54 checks PASS, all cross-references valid |

## Notes

- Slack MCP server je **externí** — AID plugin ho neimplementuje, pouze definuje protocol. PM musí nainstalovat Slack MCP server (jako třeba `@anthropic/slack-mcp`).
- Fallback na chat je kritický — plugin musí fungovat i bez Slack (backward compatibility).
- Epic Queue je YAML-based (simple, persistent). Není to databáze — max desítky EPICů.
- MAX 1 concurrent EPIC — no parallel EPIC execution. Parallelismus je uvnitř EPICu (parallel_groups, analysis_groups).
- Timeout actions jsou conservative defaults: většina = "wait" (neudělá nic bez PM).
- Status Updates jsou fire-and-forget — nikdy neblokují execution kvůli Slack failure.
- Session 7 (E2E Test) otestuje celý Slack flow s reálným EPICem.
- Session 8 (Memory MCP) je nezávislý na Slack — ale může využít Slack pro memory-related notifikace.

---

**Status:** completed
**Last Updated:** 2026-02-17
**Completion:** 100%
