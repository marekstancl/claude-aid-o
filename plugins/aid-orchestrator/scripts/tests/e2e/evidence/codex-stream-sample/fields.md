# Codex `--json` stream shape + `--output-schema` capability — discovery evidence

**EPIC:** E-065-1_7 (P065 — C3 Cross-Provider Dispatch Bridge) · **Step 1** (e2e runtime discovery)
**Captured:** 2026-07-14 on eco (Linux) · **Codex CLI:** `codex-cli 0.143.0` (`/usr/local/bin/codex`), logged in via ChatGPT
**Model used:** `gpt-5.5` (see [§Model floor](#model-floor)) · **Harness:** [`../../discover-codex-stream.sh`](../../discover-codex-stream.sh)
**Sample:** [`events.jsonl`](events.jsonl) — a real, sanitized `codex exec --json` stream (summarize-a-file prompt, read-only sandbox).

---

## THIS FILE IS THE GROUNDING SOURCE — read it before building the following (all in LATER EPICs)

Everything the C3 bridge decodes from Codex is grounded here. Do **not** assume any event shape,
field path, or schema-enforcement behavior that is not written in this file. If Codex behavior
changes, re-run the harness and update this file first.

- **Step 5 — the `--json` stream parser** (session id, reported model, `events_valid`, token usage):
  use the exact jq paths in [§Parser field map](#parser-field-map). Note the **model gap**
  ([§Model](#model--discovery_blocker-not-in-the---json-stream)) — model is NOT in the stream.
- **Step 3 — the fake/stub Codex CLI** (used by the bats tests): it MUST emit the exact event
  vocabulary, ordering, and field nesting in [§Stream shape](#stream-shape-observed-event-vocabulary)
  and reproduce the [§Error path](#error-path-turnfailed--the-terminal-failure-shape). Model it on
  THIS captured sample, not on assumptions.
- **Step 6 — the jq raw-response validator** (the trusted gate): treat `--output-schema` as MODEL
  HELP ONLY per [§`--output-schema` empirical behavior](#--output-schema-empirical-behavior). It
  constrains shape + `additionalProperties`, but its accepted JSON-Schema subset is narrow
  (no `if/then`), so the bridge MUST validate the raw last-message itself. Do not delegate
  correctness to `--output-schema`.

No event-shape or schema-enforcement assumption remains undocumented below.

---

## Invocation that produced the sample

```bash
codex exec --json --skip-git-repo-check --ephemeral \
  --cd <TMP>/run1 --sandbox read-only -m gpt-5.5 \
  "Read sample.txt and summarize it in one sentence." < /dev/null
```

Notes that a consumer of this stream must respect:
- `--json` prints one JSON object per line to **stdout**; the human-readable header goes to **stderr**
  and is fully SUPPRESSED in `--json` mode (see [§Model](#model--discovery_blocker-not-in-the---json-stream)).
- `--ephemeral` means no rollout/session file is persisted (the bridge runs ephemeral for cleanliness;
  the session file is NOT a provenance source at runtime — see [§Session-id proof](#session-id-proof-thread_id--session_id)).
- `--skip-git-repo-check` is only needed when `--cd` is a non-git dir; the real bridge runs `--cd <repo>`
  (a git repo) so it will not need this flag. Independence is **provider + fresh process + `--sandbox read-only`**,
  NOT a filesystem read-jail.
- `< /dev/null` — redirect stdin. Codex reads stdin and appends it as a `<stdin>` block; with a positional
  prompt this is harmless, but Codex still prints `Reading additional input from stdin...` to **stderr**.
  Redirecting from `/dev/null` keeps that append empty and deterministic. It does NOT suppress the stderr
  notice; that notice is cosmetic and must be ignored by parsers (stdout-only).

---

## Stream shape (observed event vocabulary)

The `--json` stdout stream uses a **small, flat event vocabulary** (distinct from the richer record
vocabulary in the persisted rollout file). Observed, in order, in the committed sample:

| # | line `.type`        | `.item.type`        | carries |
|---|---------------------|---------------------|---------|
| 1 | `thread.started`    | —                   | `.thread_id` (**the session id** — see proof below) |
| 2 | `turn.started`      | —                   | nothing but `.type` |
| 3 | `item.completed`    | `agent_message`     | `.item.text` = a **preamble** ("I'll read the file…") — NOT the answer |
| 4 | `item.started`      | `command_execution` | `.item.command`, `.item.status="in_progress"`, `.item.exit_code=null` |
| 5 | `item.completed`    | `command_execution` | `.item.command`, `.item.aggregated_output`, `.item.exit_code=0`, `.item.status="completed"` |
| 6 | `item.completed`    | `agent_message`     | `.item.text` = the **final answer** (last agent_message before terminal) |
| 7 | `turn.completed`    | —                   | `.usage.{input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens}` |

- Lines 4–5 (`command_execution`) appear **only when the model runs a shell command** (it did, to read
  the file). A trivial prompt that needs no tool call omits them (verified: a bare `--output-schema` run
  produced `thread.started → turn.started → item.completed(agent_message) → turn.completed`). So the
  parser must NOT assume a fixed line count — it must key off `.type`/`.item.type`, never position.
- There can be **multiple `agent_message` items** (a preamble + the answer). The final answer is the
  **LAST** `item.completed`+`agent_message` before the terminal event, NOT the first. See parser map.
- **Stability:** the harness runs the identical prompt twice and asserts the event-type sequence is
  byte-identical across both runs before writing evidence (gate). Both runs produced the exact sequence
  above. `.usage` numbers differ per run (expected — not a stability field).
- `.item.aggregated_output` echoes the shell command's stdout and **can leak absolute paths** (e.g. a
  `pwd`). This is why `events.jsonl` is passed through the harness scrubber before commit
  (see [§Sanitization](#sanitization)).

### `command_execution` caution for the parser
`.item.command` and `.item.aggregated_output` are **untrusted, model-driven** content. The parser must
treat them as data only. They are NOT part of C3 provenance and should not be parsed for meaning.

---

## Parser field map

Exact jq paths for the Step-5 parser. All verified against the committed [`events.jsonl`](events.jsonl).

### Session id — `thread.started.thread_id`
```bash
jq -r 'select(.type=="thread.started") | .thread_id' events.jsonl
# -> 019f6177-6b84-7ed3-8969-e8495959a7fa   (UUIDv7, first line of the stream)
```
This is the authoritative session identifier available in the stream.

#### Session-id proof: `thread_id == session_id`
The stream label is `thread_id`; the human header and rollout call it `session id`. They are the **same
value**. Proof (non-ephemeral run, so a rollout file persisted):
- stream `thread.started.thread_id` = `019f616e-bd8c-7bf2-a2ae-dcdd561894a8`
- the persisted rollout was named `rollout-2026-07-14T18-21-15-019f616e-bd8c-7bf2-a2ae-dcdd561894a8.jsonl`
  and its `session_meta` record had `payload.session_id == payload.id == 019f616e-bd8c-7bf2-a2ae-dcdd561894a8`.
So `thread_id` (stream) IS the session id. The bridge, which runs `--ephemeral`, must take the id from
`thread.started.thread_id` — the rollout file will not exist.

### Completion (terminal) event — `turn.completed`
```bash
jq -c 'select(.type=="turn.completed") | .usage' events.jsonl
# -> {"input_tokens":23213,"cached_input_tokens":13568,"output_tokens":118,"reasoning_output_tokens":0}
```
`turn.completed` is the terminal event of a **successful** turn and is the only line carrying `.usage`.
Its presence as the LAST line is the success signal (see `events_valid` below).

### Final answer (the C3 report body) — LAST `agent_message`
```bash
# Streaming parsers: keep overwriting a var with each agent_message text; the last wins.
# Batch (slurp) form, verified:
jq -rs 'map(select(.type=="item.completed" and .item.type=="agent_message")) | last | .item.text' events.jsonl
```
Do NOT use `first`/`head -1` — that returns the preamble.

### `events_valid` provenance signal
A stream is a well-formed, completed turn iff **all** hold:
1. first line `.type == "thread.started"` and `.thread_id` is a non-empty UUID;
2. last line `.type == "turn.completed"` (NOT `turn.failed`, see error path);
3. no `.type == "error"` line present;
4. at least one `item.completed`+`agent_message` (the answer exists).
```bash
first=$(jq -rs '.[0].type' events.jsonl); last=$(jq -rs '.[-1].type' events.jsonl)
# committed sample: first=thread.started  last=turn.completed  -> events_valid=true
```

### Token usage — `turn.completed.usage`
Keys: `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens` (all integers).

---

## Model — DISCOVERY_BLOCKER (not in the `--json` stream)

> **DISCOVERY_BLOCKER (scoped, RESOLVED for the bridge):** the reported model is **absent from the
> `codex exec --json` stdout stream**. `grep` for the model slug across full streams returns **0 matches**.
> There is no `thread.started.model`, no per-turn model event — nothing. The plan's architecture note
> ("provenance … reported model … is parsed from the Codex `--json` stream") is **empirically false** for
> CLI 0.143.0. This is a real gap and is recorded here as the gate requires.

Where the model actually appears (NONE of these is the stdout `--json` stream):
1. **Human-readable header** (stderr, only in NON-`--json` mode): `model: gpt-5.5`, alongside
   `session id:` and `provider: openai`. `--json` mode suppresses this header entirely.
2. **Persisted rollout file** (only when NOT `--ephemeral`): a `turn_context` record with
   `.payload.model == "gpt-5.5"`. `session_meta.payload` has only `model_provider`, not the model slug.
   The bridge runs `--ephemeral`, so this file does not exist at runtime.

**Resolution for Step 5 / the bridge — do NOT source model from the stream:**
- The bridge INVOKES Codex with an explicit `-m <model>` (or `-c model=<model>`). That argument is the
  bridge's own controlled input and is the authoritative "reported model" for provenance — record the
  **requested** model, not a stream-parsed one.
- Optionally cross-check by capturing the NON-`--json` stderr header in a parallel/duplicate invocation,
  but that costs a second run and is not required. The `-m` argument is sufficient and trustworthy.
- The harness emits a `NOTE:` to stderr if a future Codex build ever starts putting the slug in the
  `--json` stream, so this gap is re-evaluated rather than silently assumed. **Step 5 must not block on
  a stream model field; it must read model from the dispatch's own `-m`.**

This blocker does **not** sink the EPIC: session id and completion event (the other two gated fields)
are present and stable, and model has a concrete, trustworthy alternative source (the bridge's `-m`).

---

## Error path (`turn.failed`) — the terminal failure shape

When the turn fails (e.g. the API rejects the request), the terminal event is **`turn.failed`**, not
`turn.completed`, and an **`error`** line precedes it. The fake CLI (Step 3) must reproduce this shape,
and `events_valid` must treat it as invalid. Captured from the `--output-schema` if/then probe:

```json
{"type":"thread.started","thread_id":"019f6171-8c97-7331-b5ac-c158fb67b075"}
{"type":"turn.started"}
{"type":"error","message":"{ ...invalid_request_error... 'if' is not permitted... status 400 }"}
{"type":"turn.failed","error":{"message":"{ ...same 400 blob... }"}}
```

- `.type=="error"` carries `.message` (a **stringified JSON blob** from the backend).
- `.type=="turn.failed"` carries `.error.message` (same blob).
- The blob, once `fromjson`-parsed, has `.status` (e.g. `400`), `.error.code`
  (e.g. `invalid_json_schema`) and `.error.message` (human text). CLI process exit code was `1`.

---

## `--output-schema` empirical behavior

`--output-schema <FILE>` is forwarded to the OpenAI backend as a **strict structured-output**
`response_format` named `codex_output_schema`. Empirically, on CLI 0.143.0 + `gpt-5.5`:

| Capability probed | Result | Evidence |
|-------------------|--------|----------|
| **(a) constrains last-message to the schema shape** | **YES** | With an accepted schema, the final `agent_message.text` (and `-o` last-message file) is exactly the schema-shaped JSON object, e.g. `{"verdict":"fail","reason":"requested"}` — no prose, no tool preamble. |
| **(b) honors top-level `additionalProperties:false`** | **YES (enforced)** | Prompt explicitly demanded extra top-level fields `confidence` (0.9) and `notes` ("hello"). Output contained ONLY `verdict` + `reason`; both extras were dropped. The model cannot emit fields outside the schema. |
| **(c) honors a JSON-Schema `if/then` rule** | **NO — rejected outright** | With the committed probe schema (which contains one `if/then`), the request fails BEFORE generation: HTTP `400 invalid_json_schema` — `Invalid schema for response_format 'codex_output_schema': In context=(), 'if' is not permitted.` Stream emits `error` + `turn.failed`, exit 1. |

**Interpretation (this is the H1 finding):** `--output-schema` buys **object-shape + `additionalProperties`
enforcement**, but only over the **OpenAI strict-structured-output keyword subset** (`type`, `properties`,
`enum`, `required`, `additionalProperties`, nesting). Conditional/combinator keywords (`if`/`then`/`else`,
and by extension `allOf`/`anyOf`-conditionals/`not`/`$ref`-heavy schemas) are **not accepted** — they hard-fail
the request. Therefore:

- **`--output-schema` is MODEL HELP, never a trusted validator.** It cannot express the C3 report's
  conditional rules, and even the shape guarantee is only as good as the backend's strict-mode subset.
- **Consequence for Step 4** (`c3-codex-response.schema.json`): if that real schema is EVER passed via
  `--output-schema`, it MUST stay inside the strict subset (no `if/then/else`, no unsupported combinators)
  or Codex will 400. Conditional C3 rules must live in the bridge's own validator, not in `--output-schema`.
- **Consequence for Step 6** (jq raw-validator): the bridge validates Codex's raw last-message ITSELF.
  `--output-schema` at most reduces the odds of a malformed shape; it is not the gate.

### Probe schema owned by THIS step
[`../../fixtures/c3-output-schema-capability-probe.json`](../../fixtures/c3-output-schema-capability-probe.json)
— a minimal, self-contained schema (`additionalProperties:false` object + one `if/then` rule) whose ONLY
purpose is this capability measurement. It deliberately has **no dependency** on Step 4's real
`c3-codex-response.schema.json`.

---

## Model floor

- CLI **0.143.0** is installed (meets the plan's `>= 0.143.0` floor). `codex doctor` reports a newer
  0.144.4 exists but is not installed; do NOT rely on version-specific behavior beyond what 0.143.0 shows.
- The `~/.codex/config.toml` default model `gpt-5.6-sol` is **NOT recognized** by this build
  (`Model metadata for 'gpt-5.6-sol' not found` → 400). `gpt-5-codex` and `gpt-5` are rejected for
  ChatGPT-account auth ("not supported when using Codex with a ChatGPT account").
- **`gpt-5.5`** (via `-m gpt-5.5` or `-c model=gpt-5.5`) works and is the newest slug this build accepts
  on this account. The harness defaults to it (`--model` overrides). Embedded slugs in the binary:
  `gpt-5.2`, `gpt-5.3-codex`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.5`.
- Do NOT run `codex update` / touch global npm — the install is root-owned (EACCES) and 0.143.0 suffices.

---

## Sanitization

`events.jsonl` is scrubbed by the harness before commit (`sanitize()` in
[`../../discover-codex-stream.sh`](../../discover-codex-stream.sh)). Replacements:
`$HOME → <HOME>`, `$TMPDIR/<dir> → <TMP>`, the mktemp workdir `→ <TMP>`, the local username `→ <USER>`,
`sk-… → <REDACTED_TOKEN>`, `ghp_… → <REDACTED_TOKEN>`, JWT-shaped `eyJ….….… → <REDACTED_JWT>`.
Verifiable offline: `discover-codex-stream.sh --sanitize-stdin` scrubs stdin and exits (no network).
Verified self-test: `{$HOME/secret/dir, $TMPDIR/tmp.abc/run1, <username>, sk-…, eyJ….….…}` →
`{<HOME>/secret/dir, <TMP>/run1, <USER>, <REDACTED_TOKEN>, <REDACTED_JWT>}`.
The committed sample passed a leak scan (no `/home/`, no `/tmp/…`, no username, no token shapes).

---

## Edge cases resolved (from the plan's Edge Cases list)

- **Fields under a different JSONL shape than assumed** → resolved: the stream vocabulary is the flat
  `thread.*/turn.*/item.*` set above, NOT the richer rollout record set. Documented in [§Stream shape](#stream-shape-observed-event-vocabulary).
- **Session id appears only in a non-terminal event** → yes: it is in `thread.started`, the FIRST event.
  Documented; the parser reads it there (it is stable and present on line 1).
- **Model reported per-turn vs per-session** → neither in the stream; it is a config/argument-level value.
  Authoritative source = the bridge's `-m` argument. Documented in [§Model](#model--discovery_blocker-not-in-the---json-stream).

---

**Last Updated:** 2026-07-14
