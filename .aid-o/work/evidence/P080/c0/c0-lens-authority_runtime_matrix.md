# C0 lens: authority_runtime_matrix — P080 (observe, advisory)

_generated_by: aid-orchestrator:verifier@c0-lens-authority_runtime_matrix
_generated_at: 2026-08-11T04:30:00Z
Reviewed-Head: 6154ebd714cc69ffa4dd222542cf1e820e078ab8

stop_rule_blockers:
  - id: C0-AUTH-1
    step: 16
    claim: "Step 16 creates `/opt/eco/docs/docs/aid/specs/artifact-templates.md` (plus a `_category_.json`) in a DIFFERENT git repository — VULCAN-DOCS — with no declared commit/PR authority, no scoping declaration, and no evidence binding. The only guard the plan defines is a filesystem probe (`test -w /opt/eco/docs/docs/aid`), which tests permission, not authorization. An EPIC branch in aid-orchestrator cannot commit into VULCAN-DOCS; the write would land as an untracked stray file in a repo whose gates, review and release AID does not run."
    evidence: |
      Plan line 559: "Create: `/opt/eco/docs/docs/aid/specs/artifact-templates.md` — CROSS-REPO deliverable (the docs repo, not this repo)".
      Plan line 567: "The cross-repo write is attempted only after `test -w /opt/eco/docs/docs/aid` confirms access".
      `git -C /opt/eco/docs remote -v` → `git@github.com:marekstancl/VULCAN-DOCS.git` (separate repo; aid-orchestrator remote is a different repo).
      `ls -ld /opt/eco/docs/docs/aid` → exists, `drwxrwxr-x marekstancl` — so `test -w` will pass for the human user and the write proceeds with no commit story; the plan never says who commits, on which branch, or how the docs repo reviews it.
      Plan line 581 (AC): "The Docusaurus page exists at the primary path OR the fallback path exists" — file existence is accepted as done; nothing asserts the docs repo accepted it.
  - id: C0-AUTH-2
    step: 5
    claim: "The two-owner model (init creates / setup mutates) for `project.yaml` is contradicted by a THIRD writer already shipped: the project-scanner agent. Mode B (Deep Analysis) is triggered by the Orchestrator post-milestone — neither `/aid-init` nor `/aid-setup` — and outputs an extended `project.yaml`; the agent additionally declares overwrite semantics that conflict with the setup module's merge semantics. Step 5 declares a single owner without accounting for this writer, so the declared invariant is false on the shipped tree the moment it is written."
    evidence: |
      `agents/project-scanner.md:46-50`: "### B) Deep Analysis (milestone / on-demand) — **Triggered by:** Orchestrator (post-milestone) or manual request … **Output:** Extended `project.yaml` + `deep-analysis-report.md`".
      `agents/project-scanner.md:1097-1098`: "The `project.yaml` is a living document. Each scan overwrites the previous version."
      vs `skills/setup/project-scan.md:43,48`: "merge changes into existing `config/project.yaml` (preserve custom fields)" / "Never overwrite custom fields the user added".
      vs `skills/memory.md:72`: "NEVER write to project.yaml (read-only, auto-generated)".
      Plan line 205 declares only: "`project.yaml` — init auto-detects and creates, setup's project-scan module owns re-detection updates."

matrix:
  - artifact: /opt/eco/docs/docs/ecosystem/specs/artifact-standard.md
    declared_owner: "ecosystem (frontmatter `owner: Marek`, `status: published`, VULCAN-DOCS repo)"
    other_writers_found: "none from P080 — the plan correctly consumes it (lines 34, 364) and never edits it"
    crosses_boundary: no
  - artifact: /opt/eco/docs/docs/aid/specs/artifact-templates.md (+ _category_.json)
    declared_owner: "VULCAN-DOCS repo (different git remote); P080 Step 16 asserts the write"
    other_writers_found: "n/a — the issue is that P080 writes at all, with only `test -w` as authorization"
    crosses_boundary: yes
  - artifact: .aid-o/config/permissions.yaml
    declared_owner: "init creates / setup owns later changes (plan line 205)"
    other_writers_found: "readers only outside those two: `aid-release-policy.sh:350`, `lib/delivery-checks/dg12-authority.sh:63` (no writes found). `permissions-auto.yaml` is a sibling the plan explicitly parks (line 210)."
    crosses_boundary: no
  - artifact: .aid-o/config/project.yaml
    declared_owner: "init creates / setup project-scan module owns re-detection (plan line 205)"
    other_writers_found: "project-scanner agent Mode A (triggered by `/aid-setup`), Mode B (triggered by Orchestrator post-milestone — third authority), and `skills/memory.md:72` declaring it read-only"
    crosses_boundary: yes
  - artifact: .aid-o/config/integrations.yaml
    declared_owner: "init writes only `memory.enabled: true` at creation / setup owns enable-disable (plan line 205)"
    other_writers_found: "`commands/aid-init.md:404` sets `memory.enabled: true` inside the MEMORY step (not at file creation) — a run-time init mutation, not a creation-time default; `skills/setup/integrations.md:38` is the setup writer. No third writer."
    crosses_boundary: no
  - artifact: CLAUDE.md (consumer project root)
    declared_owner: "setup's claude-md module = sole AID writer (plan line 205)"
    other_writers_found: "the shipped module itself already scopes to a delimited AID section (`skills/setup/claude-md.md:63-73`); the human/user owns the rest, and in this ecosystem the file is layered (global + /opt/eco + per-project). The plan's phrase is broader than the module's actual contract."
    crosses_boundary: yes (wording only — see F3)
  - artifact: plugins/aid-orchestrator/defaults/enforcement-registry.yaml
    declared_owner: "plugin repo, canonical distributed registry (file header lines 1-9)"
    other_writers_found: "root `CLAUDE.md:195` still directs contributors to a SECOND path `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`, which is gitignored (`.gitignore:87`) and does not exist on this tree"
    crosses_boundary: no (same repo) — but two contributor-facing authorities, see F5
  - artifact: plugins/aid-orchestrator/defaults/help-index.yaml
    declared_owner: "new — P080 Step 1, checked-in only, never copied into .aid-o/"
    other_writers_found: "no auto-copy risk found: `commands/aid-init.md` copies named defaults files only (`.gitignore`, hooks, `check-severity.yaml`, `config/test-audit.yaml`, CI workflow), not `defaults/*.yaml` wholesale. The `purpose`/`final_turn` columns do however become a second authority for facts owned by `commands/*.md` frontmatter and by the wiring itself — see F4."
    crosses_boundary: no
  - artifact: "run evidence dir (gate-outcome-artifact.html, plan-close-artifact.html)"
    declared_owner: "callers pass `<run_dir>` / `<out_dir>` (plan lines 392, 425)"
    other_writers_found: "Steps 10-12 never mention `lib/aid-roots.sh`, unlike Step 7 which does (line 263). A caller invoked from inside `.aid-worktrees/plan-*` with a raw relative path writes into the linked worktree; the evidence contract assumes the state root."
    crosses_boundary: yes (potential) — see F6
  - artifact: "published Artifact page (externally shareable surface)"
    declared_owner: "controller publishes (plan lines 62, 393, 426); PM is the audience"
    other_writers_found: "no consent step, no runtime content bound. Step 15 AC3 greps FIXTURES for secrets, not the rendered artifact built from a real gate report."
    crosses_boundary: yes — see F7

findings:
  - id: C0-AUTH-F1
    severity: high
    step: 16
    finding: "Cross-repo deliverable with no authorization model (blocker C0-AUTH-1). The plan treats `test -w` as the authorization gate for writing into VULCAN-DOCS, and accepts file existence as the acceptance criterion. Nothing states who commits it, on which branch, under whose review, or how it appears in AID's evidence/release."
    evidence: "Plan lines 559, 567, 581; `git -C /opt/eco/docs remote -v` = VULCAN-DOCS (different repo); `ls -ld /opt/eco/docs/docs/aid` = writable by the same OS user, so the probe will pass and hide the real question."
    recommendation: "Invert the default: make `plugins/aid-orchestrator/docs/artifact-templates-spec.md` the PRIMARY (in-repo, gated, released) deliverable, and make the Docusaurus publication an explicit PM hand-off item (page content + target path + 'PM commits in VULCAN-DOCS'), recorded in the step output. If the cross-repo write stays primary, add to Step 16: the branch/commit/PR path in the docs repo, an explicit statement that the AID run does NOT commit there, and an AC that names the hand-off artifact rather than mere file existence."
  - id: C0-AUTH-F2
    severity: high
    step: 5
    finding: "A third writer of `project.yaml` exists on the shipped tree (project-scanner Mode B, Orchestrator-triggered post-milestone), and two shipped surfaces state mutually incompatible write semantics for the same file (overwrite vs merge-preserving), while a third declares it unwritable. Step 5 will publish a single-owner sentence that main already contradicts, and Step 8's idempotency harness does not exercise the scanner path, so nothing catches it."
    evidence: "`agents/project-scanner.md:46-50` (Mode B, Orchestrator-triggered, outputs extended project.yaml); `:1097` overwrite; `skills/setup/project-scan.md:43,48` merge/preserve; `skills/memory.md:72` 'NEVER write to project.yaml (read-only, auto-generated)'. Step 5's Error Handling sweep (plan line 207) greps only `commands/aid-init.md commands/aid-setup.md skills/setup/*.md` — it cannot see `agents/project-scanner.md` or `skills/memory.md`."
    recommendation: "Widen Step 5's mandatory sweep to `agents/*.md` and `skills/*.md` (grep the four filenames repo-wide, not in three files), and adjudicate project.yaml as a three-writer file: init creates, setup/project-scan updates the detected fields, scanner (Mode A/B) writes the profile sections it owns and MUST preserve user fields. Then either fix or scope `skills/memory.md:72` and reconcile the overwrite-vs-merge conflict — a plan that declares an owner while leaving two contradictory write contracts in place ships a false invariant."
  - id: C0-AUTH-F3
    severity: medium
    step: 5
    finding: "'setup's claude-md module is the sole AID writer' of CLAUDE.md overreaches. In consumer projects CLAUDE.md is user-owned; the shipped module's real contract is narrower — it owns only a delimited `## AID Orchestrator` section, shows a diff and asks for approval before writing. The plan's sentence, read literally, claims the file rather than the section, and this ecosystem layers CLAUDE.md across three levels (global `~/.claude/CLAUDE.md`, `/opt/eco/CLAUDE.md`, per-project) that AID must not touch at all."
    evidence: "`skills/setup/claude-md.md:63-73`: 'If yes → update only the AID section, preserve everything else … Show diff to PM, ask for approval before writing … NEVER overwrite user content in existing CLAUDE.md'. Plan line 205 states the broader claim without the section qualifier."
    recommendation: "Reword to the section-scoped truth: '`CLAUDE.md` — the file is user-owned; AID writes ONLY the delimited `## AID Orchestrator` section, and only via setup's claude-md module with PM diff approval. `/aid-init` never writes CLAUDE.md content.' Add the qualifier to the Step 16 human ownership table too, so the contributor doc does not inherit the overreach."
  - id: C0-AUTH-F4
    severity: medium
    step: "1, 5, 14"
    finding: "`help-index.yaml` becomes a second authority for facts already owned elsewhere, and only one of the three columns gets a bidirectional test. `purpose` restates `commands/*.md` frontmatter `description` with no consistency assertion; `writes:` restates the Step 5 prose carve-outs with no assertion that the two agree; only `final_turn` gets a real check (Step 14 asserts `renderer:*` names an existing script). Drift between index and the owning surface is exactly the defect class this plan exists to kill."
    evidence: "Plan line 58 (row schema incl. `purpose`, `writes`, `final_turn`); line 108 (coverage cases 1-6 — none compares `purpose` to frontmatter, none compares `writes` to the carve-out prose); line 200 (Step 5 fills `writes:`); line 497 (Step 14 adds only final_turn assertions)."
    recommendation: "Either drop `purpose` as a column and derive it from frontmatter at read time, or add a coverage case asserting `purpose` == the command's frontmatter `description` (or a documented deliberate divergence flag). For `writes:`, add one assertion that each filename in a row's `writes:` has a carve-out sentence in the named command file — otherwise the ownership authority is prose-only and the column is decoration."
  - id: C0-AUTH-F5
    severity: medium
    step: "4, 16"
    finding: "Two contributor-facing authorities for the enforcement registry. Root `CLAUDE.md` mandates registering every new detection capability in `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` — a path that is gitignored and absent from this tree — while the canonical distributed registry is `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`. Steps 4 and 16 add six-plus rows and a cite-validation test to the canonical file, leaving the mandate pointing at a nonexistent second registry."
    evidence: "`CLAUDE.md:195` cites `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`; `git check-ignore -v` → `.gitignore:87` matches it; `ls` → no such file. `defaults/enforcement-registry.yaml:1-9` declares itself 'the canonical list … The seed file in docs/plans/ is now a mirror/archive'. `docs/extending-aid.md` consistently cites the canonical path."
    recommendation: "Add a one-line `CLAUDE.md` fix to Step 16 (repoint the mandate to `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`). Cheap, in-scope for a plan whose Step 4 is registry hygiene, and it removes the risk that the new cite-validation test is authoritative while the contributor instruction is not."
  - id: C0-AUTH-F6
    severity: medium
    step: "10, 11, 12"
    finding: "The renderer steps write artifacts to a caller-supplied `<run_dir>`/`<out_dir>` and never invoke the roots contract, while the same plan adds roots-vocabulary prose to init/setup (Steps 5, 7). `aid_state_root` genuinely canonicalizes a linked worktree to the primary checkout — but ONLY when called; it is not ambient. A gate-boundary invocation from inside `.aid-worktrees/plan-*` with a relative run dir writes the artifact into the worktree, where the plan's own worktree topology means it is not the evidence tree."
    evidence: "`scripts/lib/aid-roots.sh:140-170` — `aid_state_root` resolves via git common dir → primary checkout; `aid_state_path` returns `rel` UNCHANGED when pwd == root (line 172-179), so relative paths are only safe at the root. Plan line 263 (Step 7) explicitly names `lib/aid-roots.sh`; plan lines 360, 392, 425 (Steps 10-12) do not. Note also `aid_canonicalize_project_root:120-127` honours ANY directory carrying `.aid-o/work/plan-state` as a root — a worktree that acquires plan-state is accepted as-is, so the 'never a linked worktree' sentence Step 5 will write into aid-init.md/aid-setup.md is true for the common-dir path but has a documented, deliberate exception."
    recommendation: "Add to Steps 11-12: resolve the output directory through `aid_state_path`/`aid_state_root` (or require callers to pass an absolute state-root path and assert it), plus one bats case per renderer invoking from a linked-worktree fixture — mirroring Step 7's own worktree case. And soften the Step 5 roots sentence to match the code: primary checkout via the git common dir, with the named `.aid-o/work/plan-state` escape, rather than an unqualified 'never'."
  - id: C0-AUTH-F7
    severity: medium
    step: "10, 11, 12, 15"
    finding: "Publication expands who can see run internals, and the plan bounds the SHAPE of the page (7 blocks, caps) but not its CONTENT class or its authorization. Gate-outcome facts are extracted from a real merged gate report — gate names, exit codes, failure lines, waiver ids and file paths — and the controller is instructed to publish before presenting. The ecosystem standard AID binds itself to makes the producer responsible for scanning output for secrets ('u agentů to dělá verifier'); the plan's only secret check greps checked-in FIXTURES."
    evidence: "artifact-standard.md `:::danger` block — 'Hesla, tokeny, klíče … Kdo artefakt vyrábí, musí výstup kontrolovat na jejich výskyt — u agentů to dělá verifier'; and the interní/externí table — internal artifacts may carry paths/IDs, external ones require 'vždy člověkem před odesláním'. Plan line 547 (Step 15 AC3): 'No fixture contains a real secret/token pattern (grep sweep in the harness)' — fixtures only. Plan lines 393, 426: controller publishes the artifact body first, then presents the card; no PM consent step, no runtime scan."
    recommendation: "Add to Step 10 the runtime obligation the standard assigns to the producer: `aid_artifact_render` refuses (exit non-zero) when a substituted value matches the shipped secret patterns, and stamps the page with its audience class (`internal`). Add to Steps 11-12 one sentence that published pages are internal-audience only and that any external sharing is a PM action outside AID. Cheapest version: reuse whatever secret-pattern set the repo already ships rather than authoring a new one."
  - id: C0-AUTH-F8
    severity: low
    step: 8
    finding: "Init writes several files owned by the CONSUMER repo, not by AID — `.gitignore`, `.git/hooks/pre-commit`/`pre-push`, `.github/workflows/plan-boundary-required-check.yml` — and the plan's ownership adjudication covers only the four config files. Step 8 replays gitignore backfill and hook install (good), but no ownership sentence states that these are user-repo files AID only appends to within markers."
    evidence: "`commands/aid-init.md:90` (per-line gitignore backfill), `:433` (pre-commit from defaults/hooks), `:502` (pre-push), `:566` (copy CI workflow into `.github/workflows/`). Plan line 296 replays these in the test; plan line 205 adjudicates only the four config files."
    recommendation: "Add one row per user-repo file to Step 16's human ownership table with the semantics that already hold (append-within-markers / never overwrite), so the table is the full picture rather than the four-file subset."
  - id: C0-AUTH-F9
    severity: low
    step: 1
    finding: "The 'checked-in only, never copied into `.aid-o/`' property of help-index.yaml is asserted in prose with no mechanical guard. Today it holds — init copies named defaults files, not `defaults/*.yaml` wholesale — but nothing fails if a future init edit widens the copy, which would create a stale per-project second authority in every consumer workspace."
    evidence: "Plan lines 27, 75. `grep -n 'defaults/' commands/aid-init.md` shows only named copies (.gitignore, hooks/pre-commit, hooks/pre-push, check-severity.yaml, config/test-audit.yaml, ci/plan-boundary-required-check.yml, execution-stacks fragments)."
    recommendation: "One extra assertion in the Step 2 coverage test: `commands/aid-init.md` contains no copy instruction naming `help-index.yaml`. One grep, closes the class."

confidence: high
