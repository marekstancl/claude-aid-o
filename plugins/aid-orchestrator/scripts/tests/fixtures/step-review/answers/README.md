# Recorded reviewer answers for the step-review acceptance suite

One file per sample entry and flow: `<id>-baseline.md` is the answer today's
verifier card produced on 2026-09-19 (claude-sonnet-5); `<id>-<role>.json` are
the answers of the P094 engine's roles, recorded in Step 13. The nightly stub
mode of `test-step-review-acceptance.sh` replays these files and never calls a
model; the guard directory it installs makes any model call fail.
