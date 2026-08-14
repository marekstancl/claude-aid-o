#!/usr/bin/env bash
# =============================================================================
# aid-bats-permute.sh — write a case-order permutation of a bats suite
#
# WHY THIS EXISTS. bats 1.8.2 has no `--random`/shuffle, and "the cases pass in
# a different order too" is the one check that catches a fixture sharing state
# between cases — the failure mode that looks green right up until it doesn't.
# It became load-bearing with IMP-505, where the two most expensive suites
# stopped rebuilding their fixture per case and started restoring a copy.
#
# WHY NOT `bats -f "<name>"` PER CASE. Running each case alone proves each case
# passes in isolation. It cannot prove case A does not contaminate case B,
# because every invocation gets a fresh file lifecycle — which is exactly the
# thing under test. So: one file, same cases, different order.
#
# HOW THE SPLIT IS SAFE. Blocks are delimited by a line starting at column 0
# with `@test "` — no brace counting, so a heredoc or a nested `}` inside a case
# body cannot confuse it. The result is then PROVEN to be a permutation before
# it is written: the sorted multiset of lines and the set of case names must
# both be identical to the input's. A permutation that cannot prove itself is
# refused rather than run.
#
# Usage:
#   aid-bats-permute.sh <suite.bats> <seed> [out.bats]
#     seed         integer; the same seed always yields the same order
#                  (a failing order must be reproducible, not folklore)
#     out.bats     default: <suite-dir>/.permuted-<seed>-<basename>
#                  Written NEXT TO the original on purpose: a bats file resolves
#                  `load test-helpers.bash` against its own directory.
#
# stdout: the path written. Exit 0 on success, 1 on a refused permutation,
#         2 on usage error.
# =============================================================================
set -euo pipefail

[[ $# -ge 2 ]] || { echo "Usage: $(basename "$0") <suite.bats> <seed> [out.bats]" >&2; exit 2; }
src="$1"; seed="$2"
[[ -f "$src" ]] || { echo "ERROR: no such suite: $src" >&2; exit 2; }
[[ "$seed" =~ ^[0-9]+$ ]] || { echo "ERROR: seed must be an integer: $seed" >&2; exit 2; }
out="${3:-$(dirname "$src")/.permuted-${seed}-$(basename "$src")}"

python3 - "$src" "$seed" "$out" <<'PY'
import random, sys, collections
src, seed, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lines = open(src).readlines()

# Preamble = everything before the first case. Blocks = [case start, next start).
starts = [i for i, l in enumerate(lines) if l.startswith('@test "')]
if not starts:
    sys.exit("ERROR: no '@test \"' lines found — is this a bats suite?")
preamble = lines[:starts[0]]
bounds = starts + [len(lines)]
blocks = [lines[bounds[i]:bounds[i + 1]] for i in range(len(starts))]

order = list(range(len(blocks)))
random.Random(seed).shuffle(order)
permuted = preamble + [l for i in order for l in blocks[i]]

# Prove it is a permutation, not an edit. Both checks, not either.
if collections.Counter(permuted) != collections.Counter(lines):
    sys.exit("ERROR: refusing to write — output is not a line-multiset permutation of the input")
names = lambda ls: sorted(l for l in ls if l.startswith('@test "'))
if names(permuted) != names(lines):
    sys.exit("ERROR: refusing to write — the case-name set changed")

open(out, "w").writelines(permuted)
print("%s (%d cases, seed %d)" % (out, len(blocks), seed), file=sys.stderr)
PY

printf '%s\n' "$out"
