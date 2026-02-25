---
id: R-{EPIC_ID}-{run_number}
run_id: {YYYY-MM-DD}-exploration-{short-description}
type: exploration
status: active
priority: critical|high|medium|low
started: YYYY-MM-DD HH:MM CET
completed: YYYY-MM-DD HH:MM CET (if completed)
ai_agent: {AI_NAME}
epic_id: {epic-id} (if epic run)
epic_run: {N} of {M} (if epic run)
epic_file: .aid-o/02-epics/{active|completed}/{epic-id}/epic-breakdown.md (if epic run)
plan_ref: {path to plan.json or plan file} (if exists)
orchestrated: true|false (if orchestrated by Controller)
---

# Exploration: {Research Question Title}

> **Multi-Run Work?** If exploration findings suggest 3+ runs for implementation, consider creating an **Epic Breakdown** using `.aid-o/03-config/templates/epic.md`.

## Research Question
<!-- MIN: 3-5 sentences. State WHAT you're investigating, WHY the question arose, and what a GOOD ANSWER looks like.
     Bad:  "Should we use GraphQL?"
     Good: "Evaluate whether migrating from REST to GraphQL would reduce frontend data fetching
            complexity for the dashboard views. Currently each dashboard widget makes 2-3 separate
            REST calls, leading to waterfall loading and over-fetching. A successful exploration
            will quantify the reduction in network requests, identify migration effort, and produce
            a clear go/no-go recommendation with estimated implementation cost." -->

## Context
<!-- What preceded this exploration. Reference previous runs, known pain points, stakeholder requests.
     For orchestrated runs: which EPIC run is this, what was discovered before.
     For non-orchestrated: what triggered this investigation, any related ongoing work. -->

**Previous work:** {reference prior runs or "N/A — new investigation"}
**Current state:** {what exists now that prompted this exploration}
**Trigger:** {why this exploration is needed now — user request, performance issue, tech debt, etc.}

## Scope

### Time Budget

| Phase | Planned | Actual |
|-------|---------|--------|
| Research | 1h | - |
| Options Analysis | 30m | - |
| Prototype (if needed) | 1.5h | - |
| Documentation | 30m | - |
| **Total** | 3.5h | - |

### In Scope
<!-- MIN: 3 items. Be specific — name technologies, components, questions to answer. -->
- {Specific thing to investigate}
- {Specific thing to investigate}
- {Specific thing to investigate}

### Out of Scope
<!-- MIN: 2 items. Explicitly exclude related areas you will NOT investigate in this run. -->
- {What we're NOT investigating}
- {What we're NOT investigating}

### Success Criteria
<!-- MIN: 3 items. What makes this exploration "done"? These are referenced by Completion Criteria below. -->
- [ ] Understand tradeoffs between at least 2-3 options
- [ ] Have clear recommendation with reasoning
- [ ] Document findings for future reference
- [ ] Know estimated effort for implementation (if proceeding)

---

## Research Phase

<!-- Record everything you discover. Even negative results are valuable — they prevent re-investigation.
     Cite sources, link to docs, reference code paths. Future runs will rely on this section. -->

### Existing Knowledge
<!-- What do we already know? Check previous runs, project docs, codebase. -->
{What is already known from prior work, existing docs, or codebase analysis}

### External Sources
| Source | Key Insight | Relevance |
|--------|-------------|-----------|
| [Link](url) | {Main takeaway} | High/Medium/Low |

### Key Learnings
<!-- MIN: 3 items. Concrete, actionable findings from the research. -->
1. {Learning 1}
2. {Learning 2}
3. {Learning 3}

---

## Options Analysis

<!-- Every exploration MUST include a baseline (do nothing) and at least 2 real alternatives.
     Be honest about cons — the goal is informed decision-making, not selling a preferred option.
     Include effort estimates even if rough — they drive prioritization. -->

### Option 0: Do Nothing (Baseline)
**What:** Keep current approach unchanged
**Pros:** No effort, no regression risk
**Cons:** {Cons — why the status quo is insufficient}

### Option 1: {Option Name}
**What:** {Description}
**Pros:** {list}
**Cons:** {list}
**Effort:** {X hours/days}
**Risk:** {Low/Medium/High}

### Option 2: {Option Name}
**What:** {Description}
**Pros:** {list}
**Cons:** {list}
**Effort:** {X hours/days}
**Risk:** {Low/Medium/High}

<!-- Add more options as needed. -->

---

## Phases

<!-- Each phase = one research stage. Exploration runs follow a research progression:
     literature review → analysis → prototype → recommendation.
     Not all phases are required — skip Prototype if the question can be answered without code.
     Every phase MUST have all 6 subsections below. Do not skip any. -->

### Phase 1: Literature Review

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters in the exploration context. -->
{Gather existing knowledge from project docs, codebase, external sources, and prior runs. Establish what is already known and identify gaps that need deeper investigation. This phase prevents redundant work and ensures the analysis builds on solid foundations.}

**Agent / Role:** researcher

**Inputs:**
<!-- Files, context, or prior knowledge that this phase needs. -->
- {project docs, prior run references, external documentation}

**Outputs:**
<!-- Artifacts produced. Include expected file paths or section references. -->
- Populated "Research Phase" section above (Existing Knowledge, External Sources, Key Learnings)

**Constraints:**
<!-- Time limits, source restrictions, scope boundaries. -->
- {constraint — e.g., "Stay within time budget for Research phase"}

**Acceptance:**
<!-- MIN: 3 items. How we verify this phase is done. -->
- [ ] Existing Knowledge section filled with current state
- [ ] At least 3 external sources reviewed and documented
- [ ] Key Learnings contain actionable findings

### Phase 2: Options Analysis

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters. -->
{Evaluate the viable approaches identified during research. Structure each option with consistent criteria (pros, cons, effort, risk) to enable fair comparison. The baseline (do nothing) must always be included to justify any change.}

**Agent / Role:** analyst

**Inputs:**
- Key Learnings from Phase 1
- {codebase constraints, performance requirements, team capabilities}

**Outputs:**
- Populated "Options Analysis" section above with all options compared

**Constraints:**
- {constraint — e.g., "Minimum 2 real alternatives beyond baseline"}

**Acceptance:**
<!-- MIN: 3 items. How we verify this phase is done. -->
- [ ] Baseline (Option 0) documented with honest cons
- [ ] At least 2 alternative options fully analyzed
- [ ] Effort and risk estimated for each option

### Phase 3: Prototype (If Needed)

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters. -->
{Build a minimal proof-of-concept to validate assumptions that cannot be answered through analysis alone. The prototype targets the highest-uncertainty aspect of the leading option. Skip this phase if the research question can be answered without code.}

**Agent / Role:** prototyper

**Inputs:**
- Leading option(s) from Phase 2
- {relevant codebase files, APIs, libraries}

**Outputs:**
- Prototype code (disposable — not production quality)
- Measured results (performance, feasibility, complexity)

**Constraints:**
- {constraint — e.g., "Stay within prototype time budget", "Disposable code only — not for production"}

**Acceptance:**
<!-- MIN: 3 items. How we verify this phase is done. -->
- [ ] Prototype addresses the key uncertainty
- [ ] Results measured and documented
- [ ] Limitations clearly stated

### Phase 4: Recommendation

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters. -->
{Synthesize all findings into a clear, actionable recommendation. The recommendation must reference evidence from previous phases and include an implementation plan if proceeding. This is the primary deliverable of the exploration run.}

**Agent / Role:** analyst

**Inputs:**
- All findings from Phases 1-3
- Success Criteria from Scope section

**Outputs:**
- Written recommendation with rationale
- Implementation plan with effort estimate (if proceeding)
- Follow-up run or epic creation (if needed)

**Constraints:**
- {constraint — e.g., "Recommendation must address all Success Criteria"}

**Acceptance:**
<!-- MIN: 3 items. How we verify this phase is done. -->
- [ ] Clear go/no-go recommendation stated
- [ ] Rationale references evidence from research and analysis
- [ ] Implementation plan with effort estimate provided (if go)

---

## Dependencies

<!-- Which phases depend on which and why. -->

| Phase | Depends On | Reason |
|-------|-----------|--------|
| Phase 2 | Phase 1 | Needs research findings to identify viable options |
| Phase 3 | Phase 2 | Needs leading option identified for prototyping |
| Phase 4 | Phase 1, 2, 3 | Synthesizes all prior findings into recommendation |

---

## Completion Criteria

<!-- Exploration runs don't have automated quality gates. Instead, verify that all
     Success Criteria from the Scope section are met. Reference each criterion explicitly. -->

- [ ] All Success Criteria from Scope section are satisfied
- [ ] Research question has a clear, evidence-backed answer
- [ ] Findings are documented well enough for a different agent to act on them
- [ ] If recommending implementation: effort estimate and run plan provided
- [ ] If recommending no action: rationale documented for future reference

---

## Documentation Updates

- [ ] Research document created
- [ ] Architecture decision documented (if applicable)
- [ ] `CHANGELOG.md` entry added (if prototype committed)

**See:** `skills/agent-core.md` for documentation dependency tables

---

## References

**External Sources:** [Source](url)
**Related Runs:** [Previous run](../archive/{run-id}.md)
**Commits:** `{hash}` - {message} (if prototype created)

---

## AI Run Log

**{Timestamp}** - {Action/Decision}

---

## Completion Checklist

### Pre-Completion:
- [ ] Research question answered
- [ ] Options analyzed with evidence
- [ ] Recommendation provided with rationale
- [ ] Findings documented for future reference

### Run Closure:
- [ ] Commit messages follow conventions
- [ ] Run file archived to completed/
- [ ] Handoff protocol executed (see `skills/run-management.md`)
- [ ] Run log updated

---

## Next Steps

**For Human Review:**
- Review recommendations and evidence
- Decide on implementation approach

**For AI (if run continues):**
- Implement recommended approach
- Create epic breakdown for implementation (if multi-run)

---

**Status:** {active|blocked|completed}
**Last Updated:** {YYYY-MM-DD HH:MM CET}
**Completion:** {%}
