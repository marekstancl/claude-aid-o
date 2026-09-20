# Plan-final sabotage set

Four fixture plans that the close of a plan must judge correctly. A decision
that can only refuse is as useless as one that can only pass, so the set holds
one healthy plan and three with exactly one defect each. The suites build the
fixtures from this description on every run; nothing here is a stored repository.

| Fixture | What is wrong | Verdict `decide` must give |
|---|---|---|
| `healthy` | nothing: gates green, the cp7 round closed at the candidate with no open blocker, obligations settled, only AID's own bookkeeping (`.aid-o/config/counter.yaml`) modified in the tree | `release_ready: true`, no blocker, no waiver |
| `open-blocker` | the cp7 round is closed with one open blocker that no PM-accepted dispute carries | `release_ready: false`, blocker `final_review` |
| `red-gate` | one required gate row in `gates_report.json` failed | `release_ready: false`, blocker `gates_report` |
| `unsettled-obligation` | an obligation of the plan is neither done nor waived | `release_ready: false`, blocker `obligations` |

Where they run:

- `scripts/tests/bats/test-release-policy.bats` and `test-evidence-verify-tree.bats`
  hold the `healthy` half today (the verification report passes with the counter modified).
- `scripts/tests/bats/test-plan-final-decide.bats` builds all four against stage `decide`.
- The testbed (`/opt/eco/projects/aid-testbed`, `fixtures/plan-final-*`) mirrors
  the same four against the installed plugin after a release. The two surfaces
  carry the same names so they cannot drift apart unnoticed.
