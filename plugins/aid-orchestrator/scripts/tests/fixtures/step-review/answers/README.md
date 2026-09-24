# Recorded reviewer answers for the step-review acceptance suite

One file per sample entry and flow: `<id>-baseline.md` is the answer today's
verifier card produced on 2026-09-19 (claude-sonnet-5); `<id>-<role>.json` are
the answers of the P094 engine's roles, recorded in Step 13. The nightly stub
mode of `acceptance-step-review.sh` replays these files and never calls a
model; the guard directory it installs makes any model call fail.

## Step 13 (2026-09-19)

`<id>-<role>.json` are the Sonnet run's answers (all 20 entries, 22 files;
the stub mode replays these). `<id>-<role>.opus.json` are the Opus run's
answers for the eight entries it completed before the 30 USD ceiling (the six
failing entries plus s07 and s11). The reviewers' `evidence` and `command`
fields are exactly what they wrote; the adjudicator's verdict on each is in
`acceptance.json` (`rejected` counts the findings whose evidence did not
resolve).
