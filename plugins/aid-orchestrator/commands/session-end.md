Complete and archive the current session.

Read `skills/session-management.md` and follow the Completion protocol.

Steps:
1. Run final quality gates (tests pass, docs updated, no TODO/FIXME)
2. Update session file: Status = Completed, list all commits and files changed
3. Generate completion summary (duration, commits, files, what was accomplished)
4. Archive: move session file from `.aid-o/04-engine/sessions/` to `.aid-o/04-engine/sessions/archive/`
5. Update `.aid-o/04-engine/memory/active-work.md` — mark current focus complete, add to Recent Work, update Next Steps
6. **Memory indexing** (per `skills/memory-mcp.md` → `memory_index_session()`):
   - Read `.aid-o/03-config/policies/memory-config.yaml`
   - IF `memory.enabled` AND `memory.auto_index.session_end`:
     - Index decisions from session log → `qdrant-store` (type: decision)
     - Index new lessons from `lessons-learned.md` → `qdrant-store` (type: lesson)
     - Index new commands from `command-history.md` → `qdrant-store` (type: command)
   - IF disabled or fails → skip silently, session still completes
7. Ask PM: "Session complete. Archive or continue?"
