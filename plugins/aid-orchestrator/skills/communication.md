---
name: communication
description: Shared contract for every final message AID puts in front of the PM — the four decision cards, the output-product table, the ordering rule and the language rule
user_invocable: false
---

# Communication — Decision Cards and Output Products

**Last Updated:** 2026-08-12

Every message AID leaves the PM with at a boundary is one of four small cards:
outcome first, plain language, one recommended action. This file defines those
cards, each output product's audience and the language rule; other surfaces
reference it, never restate it.

## When to Invoke

Invoke when rendering the final chat message at an FSM or plan boundary, a
block/escalation/force path or a delegated-agent completion; when changing a
deterministic renderer (`scripts/lib/aid-*-summary.sh`); and when adding a
public command surface, whose `final_turn` row must name a renderer or card
type first. Do NOT invoke for machine artifacts (JSON evidence, protocol
files, run state) or documents with their own template.

## Output Products (D16)

| Product | Audience | Form | Owner and rule |
|---|---|---|---|
| **Decision handoff** | PM in the active chat | short, natural language in the PM's language | the **controller**, never a delegated implementer; rendered at a real decision/change/block boundary; says what happened and what to do now |
| **Evidence record** | controller, later agent, CI/audit tooling | canonical structured data plus only indispensable raw material | the producing script or agent; proves a fact, binds it to input/HEAD or enables recovery — not a second chat transcript. A Markdown report needs an identified consumer, producer, input and retention class |
| **On-demand detail view** | PM asking "why / show evidence" | deterministic rendering from canonical evidence | the controller, on request; expands the handoff, never has an agent invent a retrospective story |

## The Four Cards (D17)

A skeleton, not a licence to pad empty sections. Cards render in the PM's
language; **these examples are Czech because the requirements were** — the
structure binds, not the wording.

**1. Finished — no PM decision.**

```text
Hotovo: <plain-language outcome>.
Změnilo se: <1–3 user-relevant effects>.
Ověřeno: <tests/gates or "neověřeno", with the reason>.
Další krok: <one concrete recommendation, or "nic dalšího není potřeba">.
```

**2. Decision required.**

```text
Potřebuji tvoje rozhodnutí: <one question>.
Proč teď: <plain consequence of waiting/choosing>.
Doporučení: A — <recommended action and consequence>.
Alternativy: B — <meaningful alternative>; C — <stop/defer when relevant>.
Riziko / co není ověřeno: <only material uncertainty>.
```

**3. Blocked or failed.**

```text
Zastaveno: <the concrete blocker, not an internal error label>.
Dopad: <what has not happened and what remains safe>.
Doporučené řešení: <smallest safe action>.
Pokud chceš převzít riziko: <the exact public --force command/decision>,
<what it will and will not override>.
```

**4. Progress / handoff between agents.** One short status line while work is
ongoing; at a true boundary use one of the three cards above. Never paste logs,
paths, raw JSON or a chain of thought by default. `awaiting_host_resume` is a
specialization owned by `commands/aid-run.md`.

## Ordering, Truth and Publication

- **Ordering** — identifiers and a detail link are optional **final** lines:
  state the decision before naming a checkpoint, SHA, FSM state or file.
- **Truth** — never claim completion from a delegated agent's assertion; a
  renderer reads only the canonical controller verdict.
- **Inventory** — a path absent from the output-contract inventory cannot
  quietly emit a final technical dump: every public row of
  `defaults/help-index.yaml` carries `final_turn` (`renderer:<script>`,
  `card:<type>`, `internal`).
- **Publish before present** — a renderer emits the chat card on stdout and an
  artifact body file; every wiring site carries the clause below VERBATIM, one
  literal that `scripts/tests/test-communication-wiring.sh` enforces. Live
  publication is the controller's act; no script claims a page was published.

```text
Publish the artifact body via the Artifact tool, then present the chat card verbatim.
```

## MUST Rules

1. **MUST** use one of the four cards at every boundary — no free-form dumps.
2. **MUST** lead with the outcome, identifiers and paths last.
3. **MUST NOT** define a card shape outside this file — quote a rendered
   example, never re-specify the skeleton.
4. **MUST** render cards in the PM's conversation language; documents follow
   `document_language` in `defaults/orchestration.yaml` (`EN`), its only home.
5. **MUST NOT** state a completion, pass or published page the canonical
   controller verdict does not carry.
6. **MUST** carry the publish clause verbatim at every renderer wiring site.
   `/aid-audit-tests` takes card vocabulary from here; its own renderer mandate
   stays authoritative for what that command emits.

## Completeness Gate

- [ ] Four skeletons structurally unmodified; D16 table covers all 3 products.
- [ ] Language rule cites `defaults/orchestration.yaml` and no other path.
- [ ] Publish clause literal appears once, fenced; file under 120 lines.

## Reference Files

- `defaults/help-index.yaml` — `final_turn` column (output-contract inventory).
- `scripts/lib/aid-artifact-render.sh` — artifact body skeleton.
- `scripts/tests/test-communication-wiring.sh` — wiring guard for this file.

**Last Updated:** 2026-08-12
