Complete and archive the current session.

Read `.claude/skills/session-management/instructions.md` and follow the Completion protocol.

Steps:
1. Run final quality gates (tests pass, docs updated, no TODO/FIXME)
2. Update session file: Status = Completed, list all commits and files changed
3. Generate completion summary (duration, commits, files, what was accomplished)
4. Archive: move session file from `workspace/sessions/active/` to `workspace/sessions/completed/`
5. Update `workspace/session-log.md` — add entry at TOP (reverse chronological)
6. Update `workspace/active-work.md` — mark current focus complete, add to Recent Work, update Next Steps
7. Ask PM: "Session complete. Archive or continue?"
