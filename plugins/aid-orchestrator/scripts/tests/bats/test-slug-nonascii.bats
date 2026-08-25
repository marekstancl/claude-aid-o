#!/usr/bin/env bats
# aid-tier: t0
# test-slug-nonascii.bats — a non-ASCII plan title must not reach a filename.
#
# WHY THIS SUITE EXISTS: P087 (2026-08-25) generated EPIC files named
# `E-087-1_2-\200\224-paraleln-...md` — the tail of an em dash, raw, in a
# filename. The recorded epic_path then differed byte-for-byte from the file on
# disk and the generation receipt failed with "missing EPIC evidence", which
# names the wrong thing entirely. Two causes, both covered here: an awk bracket
# expression is a BYTE set, so `[—–-]` ate one byte of a three-byte dash; and
# slugify ran under a UTF-8 locale, where a multibyte character can survive
# `[^a-z0-9]` and `cut -c` can split it.

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${PLUGIN}/scripts/lib/common.sh"
}

@test "slug of a Czech title is pure ASCII" {
  run slugify "P087 — Paralelní běh agentů, chybějící hooky a věrohodné UI návrhy"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-z0-9-]+$ ]] || { echo "non-ASCII in slug: $(printf '%s' "$output" | od -c | head -2)"; false; }
}

@test "slug of a title that is ONLY punctuation and diacritics is still a usable name" {
  run slugify "— – ěščřž"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-z0-9-]*$ ]]
  [[ "$output" != *$'\200'* ]]
}

@test "slug never ends in a dash, even when the cut lands on one" {
  run slugify "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa — tail"
  [ "$status" -eq 0 ]
  [[ "$output" != *- ]]
}

@test "the title extractor strips a whole em dash, not one of its bytes" {
  run bash -c 'printf "# P087 — Paralelní běh\n" | awk "/^# P[0-9]/ { sub(/^# P[0-9A-Za-z-]+[[:space:]]*(—|–|-)[[:space:]]*/, \"\"); print; exit }"'
  [ "$status" -eq 0 ]
  [[ "$output" == "Paralelní běh" ]] || { echo "got: $(printf '%s' "$output" | od -c | head -2)"; false; }
}

@test "ASCII titles slug exactly as before" {
  run slugify "P084 - cilenost a riziko"
  [ "$status" -eq 0 ]
  [ "$output" = "p084-cilenost-a-riziko" ]
}
