P080 Step 15 — generated goldens. DO NOT hand-edit.

Each *.blocks.txt is the artifact BODY's block order (headings and structural
markers, in document order) for one rendered case, after the normalisation
that scripts/tests/test-integration-handoff-rendering.sh applies in the open
(temp dir -> <WORK>, repo root -> <REPO>, ISO timestamp -> <TS>).

Regenerate deliberately, never off a failure:

  AID_HANDOFF_GOLDEN_REGEN=1 bash plugins/aid-orchestrator/scripts/tests/test-integration-handoff-rendering.sh

That mode prints the diff it applied and exits 2. It never reports a pass, and
nothing but a human setting that variable can trigger it.
