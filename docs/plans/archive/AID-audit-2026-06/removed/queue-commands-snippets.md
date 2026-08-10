# Removed: aid-status queue pause/resume/reorder commands — archive

P041 fix Wave 2 (2026-06-01). The `/aid-status queue pause`, `queue resume`, and
`queue reorder` subcommands were removed: they had NO backing script (only `queue add`
is implemented, via aid-queue-add.sh) — documented-but-unenforced features (Principle #1
violation). PM never used them. **Archived here, restorable.** The `/aid-stop` command and
`/aid-run --resume` are NOT removed (they're autonomous-mode safety; being fixed separately).

To restore: paste each block back at its cited location.

---

### `commands/aid-status.md` — usage lines (were :16-18)
```
/aid-status queue pause                      # pause auto-pickup
/aid-status queue resume                     # resume auto-pickup
/aid-status queue reorder <id> --priority <level>  # change priority
```

### `commands/aid-status.md` — subcommand sections (were :128-138)
```
### `/aid-status queue pause`

Pause auto-pickup. Running task continues, no new task starts.

### `/aid-status queue resume`

Resume auto-pickup. Next task starts after current completes (or immediately if idle).

### `/aid-status queue reorder <id> --priority <level>`

Change priority of a queued task. Show new queue order.
```

### `commands/aid-status.md:178` — subcommand list
Was: `- **Queue subcommands modify** — `add`, `pause`, `resume`, `reorder` write to queue.yaml`
Now: `- **Queue subcommands modify** — `add` writes to queue.yaml`

### `commands/aid-help.md:55` — help line
Was: `  /aid-status queue pause | resume               → control auto-pickup`
(removed)

---
**Why removed:** unbacked features (no script); see `docs/plans/AID-audit-2026-06/09-command-audit.md`.
**Kept (not removed):** `queue add` (backed), the "Auto-pickup" status display (may reflect
auto-behavior), `/aid-stop`, `/aid-run --resume` (being fixed, not deleted).
