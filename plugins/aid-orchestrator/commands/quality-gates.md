Run the 6-gate pre-commit quality protocol before committing.

Read `.claude/skills/quality-gates/instructions.md` and follow it step by step.

The 6 gates (run in order):
1. **Log Analysis** (CRITICAL) — start dev servers, verify no runtime errors
2. **Documentation Impact** (CRITICAL) — identify + update all affected docs
3. **Code Cleanup** (HIGH) — remove debug statements, temp files, secrets
4. **Git Status** (HIGH) — verify correct files staged, no .env/secrets
5. **Commit Message** (MEDIUM) — `type(scope): description (YYYY-MM-DD HH:MM TZ)`
6. **Testing** (MEDIUM) — run tests, verify coverage, add regression tests

ANY gate fails → fix → re-run from Gate 1.
ALL gates pass → commit allowed.

Document results in session file (if active session).

Quick reference: `.claude/skills/quality-gates/checklist.md`
