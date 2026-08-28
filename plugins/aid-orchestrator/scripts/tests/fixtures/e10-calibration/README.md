# E10 calibration fixtures

Each directory is one entry in `manifest.json`, and the manifest is the
authority: it names the incident the fixture came from, the layer expected to
catch it, and what the old and new stacks are expected to do.

**These are minimal reproductions, not copies of run evidence.** A fixture
carries the smallest artefact that exhibits its failure class, so a test can
drive one layer without standing up a whole run. Where a fixture could not be
grounded in a real incident it is NOT here — it stays in the manifest with
`grounded: false` and the reason, because the alternative is inventing the
detail (plan decision D3).

**`negative-ordinary/` is the one that makes the others mean something.** A
dataset of nothing but defects is satisfied by a control stack that blocks
unconditionally.

**What this directory does NOT prove.** Only the classes whose catcher is a
tool that can be run directly — today `e10_preflight` — are proven caught here,
and "proven" means the suite RUNS that control against the fixture and reads its
verdict, together with the negative control, so a detector that flagged
everything would fail. For C1, C2, C3 and C4 the manifest records the
EXPECTATION; the proof is the calibration run itself (Steps 4 and 7 over this
dataset). Reading a green suite here as "every control catches its case" would
be exactly the over-claim this plan keeps removing.

The suite also checks the manifest's SHAPE — non-empty provenance, both expected
outcomes present, a catcher that exists, exclusions with reasons. That is not a
claim that the incidents are real; their reality was established by the
grounding pass and each entry carries its `source_incident` so it can be
re-checked.
