# IMP-266 — recovery ceremony for an incorrect `merged_to_plan` (Option B)

**Status:** RATIFIED — the PM chose **Option B** on 2026-07-24: `merged_to_plan`
stays deliberately terminal; an incorrect assignment is corrected by this
documented, audited human ceremony, never by an in-tool reverse transition.
**Decision brief:** [`IMP-266-merged-to-plan-recovery-DECISION.md`](IMP-266-merged-to-plan-recovery-DECISION.md).
**Scope:** doc-only. No code change — `merged_to_plan` is already terminal in
`lib/aid-plan-manifest.sh` (`_AID_EPIC_STATUS_TRANSITIONS`), and this ceremony
adds no outgoing edge to it.

## Principle

`merged_to_plan` is an accounting entry, not a whiteboard. Once the manifest
records "this EPIC was merged into the plan", that fact is **never erased or
rewritten in place**. If the merge later turns out to be wrong or incomplete,
the correction is a *new, traceable operation* — a corrective EPIC or this
audited recovery ceremony — exactly as a ledger error is fixed by a documented
adjusting entry, never by rubbing out the original line.

Why this matters mechanically: because no code path can ever reverse a delivery
claim, every reader of the state machine can treat `merged_to_plan` as a hard,
monotonic fact. The controller never has to guess whether `merged_to_plan` means
"a real, safe, proven merge" or "a state someone manually reverted". The
terminality is load-bearing in the substrate's threat model; the ceremony gives a
sanctioned correction path **without** spending that safety.

## When to run it

Only when an entry is genuinely wrong — i.e. a `merged_to_plan` entry claims a
delivery the EPIC did not make, or attributes the wrong `epic_merge_commit`. This
is **not** a normal-flow outcome: `merged_to_plan` is only reached with a
Git-proven ancestor merge commit (IMP-272 authorization + `_pfsm_is_ancestor`),
so a wrong entry requires a hand-edited manifest, a misused
`plan_manifest_set_epic_status … merged_to_plan <sha>`, or a future-caller bug.
IMP-265/267 already hardened the repair/attest paths that could produce one.

Do **not** run it to "undo" a correct merge. There is no sanctioned undo of a
correct delivery — that is the whole point of the terminal state.

## Preconditions (PM-authorized, human-reviewed)

1. Explicit PM authorization to correct the entry, with a written reason.
2. A clean working tree on the plan's `target_branch` (lifecycle writes are only
   valid there — see `aid-lifecycle.sh`).
3. The wrong `epic_merge_commit` and the affected `epic_id` / `plan_id` recorded
   in the reason text, so the correction preserves what was previously claimed.

## The ceremony

The correction is an auditable human act recorded in the **git-tracked lifecycle
manifest** and the **op log** — no generic rollback, no in-place erase.

1. **Preserve the wrong entry as history.** Do not delete or overwrite the
   `merged_to_plan` line. In the git-tracked lifecycle manifest
   (`.aid-lifecycle/manifests/P<NN>.yaml`), record the correction as a new,
   dated note that states: the affected EPIC, the prior (wrong) merge commit, why
   it was wrong, and the PM who authorized the correction. `aid_lifecycle_publicsafe_check`
   still gates the commit (no secrets / non-public-safe content).

2. **Re-scope the affected EPIC as a new unit of work.** The corrected delivery
   is a *fresh* EPIC (or a corrective EPIC), planned and merged through the
   normal plan-branch flow. It earns its own `merged_to_plan` entry the ordinary
   way — Git-proven ancestry, IMP-272 authorization — so the plan's denominator
   reflects both the original (wrong) fact and the corrective delivery.

3. **If the runtime manifest entry is damaged, rebuild it non-destructively.**
   Run

   ```
   aid-plan-fsm.sh plan-state <plan_id> --repair
   ```

   Since IMP-265, `--repair` is a byte-identical no-op on a healthy manifest and
   preserves proven siblings' attestations; it only reconstructs genuinely
   damaged entries, always as `unproven`. It never mints `proven` and never
   reverses a terminal state.

4. **Re-attest only genuinely-provable entries.** For an entry whose origin is
   actually provable from Git, attest it explicitly:

   ```
   aid-plan-fsm.sh plan-state <plan_id> --attest-source-ref <ref> \
       --reason '<why this origin is provable>' --epic <epic_id>
   ```

   Attestation's precondition IS an unproven entry (you do not need `--repair`
   first). It re-derives ancestry from Git and fails closed when the origin is
   not provable — so the ceremony can never launder a wrong entry into a proven
   one.

5. **Record the outcome.** The lifecycle-manifest note (step 1) plus the op log
   from steps 3–4 are the complete, dated, PM-authorized audit trail of the
   correction. Nothing about the original `merged_to_plan` fact was erased.

## What the ceremony deliberately does NOT do

- It does not add a `merged_to_plan → running` (or any outgoing) transition.
- It does not clear or rewrite `epic_merge_commit` on the terminal entry.
- It does not offer a generic rollback of the manifest to an earlier state.

## Future option (deferred)

If P068's dogfood shows this ceremony is too slow or error-prone in practice,
Option A (a single narrow, audited `--reopen-epic` transition gated by explicit
operator attestation) remains a clean M-effort follow-up whose design is sketched
in the decision brief. It is deferred, not rejected — but it is not needed today,
and adding it now would spend the terminality safety the ceremony preserves.

**Last Updated:** 2026-07-24
