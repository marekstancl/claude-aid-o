#!/usr/bin/env bats
# aid-tier: t2
# test-instruction-closure.bats — P076 E-076-1_3 Step 7.
#
# The Controller-boundary contract used to live in exactly ONE agent card
# (implementer.md). The other eight cards said nothing about detaching work,
# claiming stale test results, or touching controller-owned state — so the
# contract bound one agent out of nine by accident of where it was written.
#
# The fix is the anti-kockopes rule applied to instructions: the contract is
# stated ONCE, in skills/agent-protocol.md, and every card carries a reference
# marker pointing at it. This suite is that fix's enforcement mechanism:
#
#   1. CLOSURE — every file in agents/ carries the reference marker. The
#      directory is enumerated DYNAMICALLY, so a card added tomorrow without
#      the marker fails here rather than silently escaping the contract.
#   2. NO DIVERGENT COPY — no agent card restates the contract's bullets. A
#      second copy is the defect: it drifts, and then two cards disagree.
#   3. THE SOURCE EXISTS — agent-protocol.md actually carries the section the
#      markers point at, with the bullets intact. Without this, closure could
#      be "achieved" by nine references to nothing.
#
# Both file-content checks run over the body with fenced code blocks BLANKED,
# so a card quoting the contract inside an example neither satisfies (1) nor
# trips (2). The marker is a reference line, never a contract phrase.

PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
AGENTS_DIR="$PLUGIN_DIR/agents"
PROTOCOL="$PLUGIN_DIR/skills/agent-protocol.md"

# The one reference marker. Cards are checked for this exact substring.
MARKER='Read `skills/agent-protocol.md` → **Controller boundary (non-negotiable)**'

# Distinctive phrases from the contract body. Their presence in an agent card
# (outside a code fence) means a divergent copy exists.
CONTRACT_PHRASES=(
  'Do not detach long-running work with'
  'Do not call FSM transition/increment commands'
  'Do not claim a test count or pass result'
  'Never modify `plan.json`, `fsm-state.yaml`'
  'Do not run the repository-wide'
)

# _defenced <file> — the file with ``` … ``` fenced blocks replaced by blank
# lines. Quoted examples therefore match nothing, in either direction.
_defenced() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; print ""; next }
    { print (infence ? "" : $0) }
  ' "$1"
}

# _cards — every agent card, enumerated from the directory at run time.
_cards() {
  find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' | sort
}

@test "agents directory is non-empty and enumerated dynamically" {
  run bash -c "$(declare -f _cards); AGENTS_DIR='$AGENTS_DIR'; _cards | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "the shared Controller boundary section exists in agent-protocol.md" {
  [ -f "$PROTOCOL" ]
  grep -qxF '## Controller boundary (non-negotiable)' "$PROTOCOL"
}

@test "agent-protocol.md carries every contract bullet (the single source)" {
  local body missing=""
  body="$(_defenced "$PROTOCOL")"
  for phrase in "${CONTRACT_PHRASES[@]}"; do
    grep -qF -- "$phrase" <<<"$body" || missing+="  MISSING from agent-protocol.md: ${phrase}"$'\n'
  done
  if [ -n "$missing" ]; then
    printf '%s' "$missing" >&2
    return 1
  fi
}

@test "every agent card references the shared section (closure)" {
  local card bad=""
  while IFS= read -r card; do
    grep -qF -- "$MARKER" <<<"$(_defenced "$card")" \
      || bad+="  NO REFERENCE MARKER: ${card#$PLUGIN_DIR/}"$'\n'
  done < <(_cards)
  if [ -n "$bad" ]; then
    {
      echo "Every agent card must point at the shared contract. Add:"
      echo
      echo "## Controller boundary (non-negotiable)"
      echo
      echo "${MARKER}; it binds this card in"
      echo "full. The contract is stated there once and is deliberately not restated here."
      echo
      printf '%s' "$bad"
    } >&2
    return 1
  fi
}

@test "no agent card carries a divergent copy of the contract" {
  local card body bad=""
  while IFS= read -r card; do
    body="$(_defenced "$card")"
    for phrase in "${CONTRACT_PHRASES[@]}"; do
      grep -qF -- "$phrase" <<<"$body" \
        && bad+="  DIVERGENT COPY in ${card#$PLUGIN_DIR/}: ${phrase}"$'\n'
    done
  done < <(_cards)
  if [ -n "$bad" ]; then
    {
      echo "The contract lives in skills/agent-protocol.md ONLY. Replace the copy"
      echo "with the reference marker."
      printf '%s' "$bad"
    } >&2
    return 1
  fi
}

@test "a card that only QUOTES the contract in a fence does not satisfy closure" {
  local tmp="$BATS_TEST_TMPDIR/quoting-card.md"
  {
    echo '# Agent: quoting'
    echo
    echo 'Example of what the shared contract says:'
    echo
    echo '```'
    echo "${MARKER}"
    echo 'Do not detach long-running work with `nohup`.'
    echo '```'
  } > "$tmp"
  local body; body="$(_defenced "$tmp")"
  # neither satisfies the marker check …
  run grep -qF -- "$MARKER" <<<"$body"
  [ "$status" -ne 0 ]
  # … nor trips the divergent-copy check.
  run grep -qF -- 'Do not detach long-running work with' <<<"$body"
  [ "$status" -ne 0 ]
}
