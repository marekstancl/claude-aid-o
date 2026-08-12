P080 Step 15 — generated goldens. DO NOT hand-edit.

Two files per case, because one of them was doing nothing.

  <case>.blocks.txt   the artifact BODY's block order — headings and structural
                      markers, in document order. A LAYOUT SPINE. It is
                      identical across every case that renders the same blocks,
                      so on its own it detects a block moving and nothing else:
                      seven of the nine were byte-identical to one another.

  <case>.content.txt  the artifact's CONTENT — tile labels and values, every
                      list item and paragraph, the detail link, the provenance
                      footer including the redaction count. This is the golden
                      that tells the cases apart and pins the numbers, the
                      redactions and the offered commands.

Both are taken after the normalisation that
scripts/tests/test-integration-handoff-rendering.sh applies in the open
(temp dir -> <WORK>, repo root -> <REPO>, ISO timestamp -> <TS>). Every input
is a checked-in fixture, so both are fully deterministic.

Regenerate deliberately, never off a failure:

  AID_HANDOFF_GOLDEN_REGEN=1 bash plugins/aid-orchestrator/scripts/tests/test-integration-handoff-rendering.sh

That mode prints the diff it applied and exits 2. It never reports a pass, and
nothing but a human setting that variable can trigger it.
