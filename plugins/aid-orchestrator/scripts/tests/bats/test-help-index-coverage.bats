#!/usr/bin/env bats
# aid-tier: t1
# test-help-index-coverage.bats — the enforcement half of AID's help inventory.
#
# WHAT IT ASSERTS: three artifacts have to agree, or a user cannot find a
# command that exists. (1) the surfaces the repo ACTUALLY ships, enumerated
# mechanically by scripts/lib/aid-help-index.sh; (2) defaults/help-index.yaml,
# which claims to be the authority on them; (3) commands/aid-help.md, which is
# regenerated FROM the index and is the only thing a user ever reads.
#
# THE ACCEPTANCE THIS ENCODES: a newly added public command fails here until it
# is INTENTIONALLY indexed and routed. Silence is not a pass — neither an
# unindexed command, nor an indexed one parked without a topic.
#
# `index_only` IS TRANSITIONAL, NOT A RESTING PLACE. It exists so the index can
# land before the help rewrite that routes its rows. The moment a user-invocable
# surface could rest there, this suite would be decoration: the cheapest way to
# silence "your command is unrouted" would be to declare it unrouted on purpose.
# So case 8 forbids it outright for any `user_invocable: true` surface, and the
# suite is EXPECTED TO FAIL until the help rewrite flips those rows to `current`.
#
# ONE NAMED EXEMPTION, BY COMMAND NAME: `/aid-help` carries `topic: none` while
# being `update`, because the router cannot route to itself. Encoded as the
# literal name below — never as "update rows may skip routing", which would
# reopen the hole for every future row.
#
# Provenance: plan P080, EPIC E-080-1_3 Step 2.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  REPO_ROOT="$(cd "$AID_PLUGIN_PATH/../.." && pwd)"
  HELP_MD="$AID_PLUGIN_PATH/commands/aid-help.md"
  INDEX_YAML="$AID_PLUGIN_PATH/defaults/help-index.yaml"

  # yq is a repo-wide hard dependency. A missing binary is a hard failure, not
  # a green skip — a skipped coverage check reads exactly like a passing one.
  command -v yq >/dev/null 2>&1 || {
    echo "yq is required by this suite and was not found on PATH"
    return 1
  }
  [ -f "$HELP_MD" ]    || { echo "missing $HELP_MD"; return 1; }
  [ -f "$INDEX_YAML" ] || { echo "missing $INDEX_YAML"; return 1; }

  # shellcheck source=../../lib/aid-help-index.sh
  source "$AID_PLUGIN_PATH/scripts/lib/aid-help-index.sh"

  # The named exemption, in one place.
  HELP_SELF_COMMAND="/aid-help"

  # Dispositions that make a row PUBLIC — i.e. part of the bijection with the
  # enumerated surfaces. The two others are asserted separately (cases 5, 7):
  # `intentionally_internal` must NOT reach a user, `remove_or_deprecate` MAY,
  # and neither is something the enumerator can see or should have to.
  PUBLIC_DISPOSITIONS="current update index_only"

  # BOTH READERS RUN EXACTLY ONCE PER CASE, into shell state. Looking a row up
  # by re-invoking the enumerator turned a pure file-inspection suite into ~170
  # subprocesses and cost 4 s in a single case — a suite on the merge path pays
  # its cost at every merge, so the lookups are maps, not pipelines.
  # `declare -g` because a plain `declare` inside setup() would be local to it.
  declare -g INDEX_TSV ENUM_TSV
  INDEX_TSV="$(aid_help_index_rows "$INDEX_YAML")" || return 1
  ENUM_TSV="$(aid_help_enumerate_surfaces "$AID_PLUGIN_PATH")" || return 1

  declare -gA ENUM_PATH=() ENUM_FLAG=()
  local c p f
  while IFS=$'\t' read -r c p f; do
    [ -n "$c" ] || continue
    ENUM_PATH["$c"]="$p"
    ENUM_FLAG["$c"]="$f"
  done <<<"$ENUM_TSV"
}

# ─── readers ────────────────────────────────────────────────────────────────

# The two readers, replayed from the state setup() captured — never re-read.
index_rows()      { printf '%s\n' "$INDEX_TSV"; }
enumerated_rows() { printf '%s\n' "$ENUM_TSV"; }

# enumerated_commands — slash names of every shipped surface, sorted.
enumerated_commands() { enumerated_rows | cut -f1; }

# public_index_commands — slash names of the PUBLIC index rows, sorted.
public_index_commands() {
  index_rows | awk -F'\t' -v pub="$PUBLIC_DISPOSITIONS" '
    BEGIN { n = split(pub, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
    ok[$5] { print $1 }
  ' | LC_ALL=C sort
}

is_public_disposition() {
  case " $PUBLIC_DISPOSITIONS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# fenced_stripped <file> — body with fenced code blocks blanked out, line
# numbers preserved. Same awk as scripts/aid-lint-skill.sh's fenced_stripped().
fenced_stripped() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; print ""; next }
    { if (infence) print ""; else print }
  ' "$1"
}

# section_headings — every `### Topic: <t>` heading in help, outside fences.
# Fence-aware on purpose: a `### Topic:` line quoted inside an example is not
# a section, and treating it as one would let a documented example satisfy
# routing for a topic that does not exist.
section_headings() {
  [ -n "${_SECTION_HEADINGS_CACHE+x}" ] || _SECTION_HEADINGS_CACHE="$(_section_headings_scan)"
  printf '%s\n' "$_SECTION_HEADINGS_CACHE"
}

# shellcheck disable=SC2120  # takes no arguments by design
_section_headings_scan() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; next }
    !infence && /^### Topic: / { sub(/^### Topic: /, ""); print }
  ' "$HELP_MD"
}

# section_body_unfenced <topic> — the body of `### Topic: <topic>`, from its
# heading to the next outside-fence `### ` heading or EOF, with fenced content
# blanked out. Case 3 matches against THIS: a command named only inside a code
# fence has not been routed to, it has been mentioned.
section_body_unfenced() {
  awk -v want="$1" '
    /^[[:space:]]*```/ { infence = !infence; if (inside) print ""; next }
    !infence && /^### / {
      if ($0 == "### Topic: " want) { inside = 1; next }
      else if (inside) { exit }
    }
    inside { if (infence) print ""; else print }
  ' "$HELP_MD"
}

# router_topics — the topics ADVERTISED by the `## Help Topics` router table,
# i.e. the lines a user reads as "these topics exist".
router_topics() {
  awk '
    /^## Help Topics/ { inblock = 1; next }
    inblock && /^## / { exit }
    inblock && $1 == "/aid-help" && $2 ~ /^[a-z][a-z0-9_-]*$/ { print $2 }
  ' "$HELP_MD"
}

# ─── cases ──────────────────────────────────────────────────────────────────

@test "router table anchor exists in aid-help.md" {
  # Error handling: a help file that lost its router table must fail loudly
  # here, naming the anchor, instead of making cases 3-4 vacuously green.
  local topics
  topics="$(router_topics)"
  if [ -z "$topics" ]; then
    echo "FAIL: no router table found in $HELP_MD"
    echo "  expected anchor: a '## Help Topics' heading containing lines of the"
    echo "  form '/aid-help <topic>   → <description>'"
    return 1
  fi
}

@test "case 1: enumerated surfaces == PUBLIC index rows, both directions" {
  local missing extra
  missing="$(comm -23 <(enumerated_commands) <(public_index_commands))"
  extra="$(comm -13 <(enumerated_commands) <(public_index_commands))"

  if [ -n "$missing" ] || [ -n "$extra" ]; then
    echo "FAIL: shipped surfaces and help-index.yaml disagree."
    [ -n "$missing" ] && {
      echo "  SHIPPED BUT NOT INDEXED (add a row to defaults/help-index.yaml):"
      echo "$missing" | sed 's/^/    /'
    }
    [ -n "$extra" ] && {
      echo "  INDEXED BUT NOT SHIPPED (stale row, or the file moved):"
      echo "$extra" | sed 's/^/    /'
    }
    return 1
  fi
}

@test "case 2: index slash names are unique" {
  local dupes
  dupes="$(index_rows | cut -f1 | LC_ALL=C sort | uniq -d)"
  if [ -n "$dupes" ]; then
    echo "FAIL: duplicate command names in help-index.yaml:"
    echo "$dupes" | sed 's/^/    /'
    return 1
  fi
}

@test "case 3: every current|update row is routed by aid-help.md" {
  local violations="" command topic disposition body
  while IFS=$'\t' read -r command _file topic _audience disposition _rest; do
    case "$disposition" in current|update) ;; *) continue ;; esac

    if [ "$command" = "$HELP_SELF_COMMAND" ]; then
      # The one named exemption — the router cannot route to itself. Asserted
      # rather than skipped: if /aid-help ever grows a topic, say so.
      [ "$topic" = "none" ] || violations+=$'\n'"    $command: the router-self exemption requires topic 'none', found '$topic'"
      continue
    fi

    if [ "$topic" = "none" ] || [ -z "$topic" ] || [ "$topic" = "null" ]; then
      violations+=$'\n'"    $command ($disposition): no topic route — only $HELP_SELF_COMMAND may carry 'none'"
      continue
    fi

    if ! section_headings | grep -qxF "$topic"; then
      violations+=$'\n'"    $command: topic '$topic' has no '### Topic: $topic' section in aid-help.md"
      continue
    fi

    body="$(section_body_unfenced "$topic")"
    if ! grep -qF -- "$command" <<<"$body"; then
      violations+=$'\n'"    $command: '### Topic: $topic' exists but never names $command outside a code fence"
    fi
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: indexed surfaces that aid-help.md does not route to:$violations"
    return 1
  fi
}

@test "case 4: router table and topic sections agree, both directions" {
  local advertised sections missing_section missing_router
  advertised="$(router_topics | LC_ALL=C sort -u)"
  sections="$(section_headings | LC_ALL=C sort -u)"

  missing_section="$(comm -23 <(echo "$advertised") <(echo "$sections"))"
  missing_router="$(comm -13 <(echo "$advertised") <(echo "$sections"))"

  if [ -n "$missing_section" ] || [ -n "$missing_router" ]; then
    echo "FAIL: aid-help.md's router table and its topic sections disagree."
    [ -n "$missing_section" ] && {
      echo "  ADVERTISED BUT MISSING (user asks for it and gets nothing):"
      echo "$missing_section" | sed 's/^/    /'
    }
    [ -n "$missing_router" ] && {
      echo "  SECTION EXISTS BUT UNADVERTISED (user never learns it is there):"
      echo "$missing_router" | sed 's/^/    /'
    }
    return 1
  fi
}

@test "case 5: intentionally_internal rows never appear in aid-help.md" {
  local violations="" command disposition stripped
  stripped="$(fenced_stripped "$HELP_MD")"
  while IFS=$'\t' read -r command _file _topic _audience disposition _rest; do
    [ "$disposition" = "intentionally_internal" ] || continue
    if grep -qF -- "$command" <<<"$stripped"; then
      violations+=$'\n'"    $command is intentionally_internal but is named in aid-help.md"
    fi
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: internal surfaces advertised to users:$violations"
    return 1
  fi
}

@test "case 6: every index file path exists and public rows point at the surface" {
  local violations="" command file disposition enum_path
  while IFS=$'\t' read -r command file _topic _audience disposition _rest; do
    if [ -z "$file" ] || [ "$file" = "null" ]; then
      violations+=$'\n'"    $command: no 'file' column"
      continue
    fi
    if [ ! -f "$REPO_ROOT/$file" ]; then
      violations+=$'\n'"    $command: file does not exist: $file"
      continue
    fi
    is_public_disposition "$disposition" || continue
    enum_path="${ENUM_PATH[$command]:-}"
    [ -n "$enum_path" ] || continue   # case 1 owns the missing-surface report
    # `-ef` is same-file by device+inode: symlink- and `./`-proof, and a shell
    # builtin rather than two realpath processes per row.
    if ! [ "$REPO_ROOT/$file" -ef "$AID_PLUGIN_PATH/$enum_path" ]; then
      violations+=$'\n'"    $command: indexed file '$file' is not the enumerated surface '$enum_path'"
    fi
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: help-index.yaml file column:$violations"
    return 1
  fi
}

@test "case 7: non-public rows have an existing file and no topic route" {
  local violations="" command file topic disposition
  while IFS=$'\t' read -r command file topic _audience disposition _rest; do
    case "$disposition" in intentionally_internal|remove_or_deprecate) ;; *) continue ;; esac
    [ -f "$REPO_ROOT/$file" ] || violations+=$'\n'"    $command ($disposition): file does not exist: $file"
    [ "$topic" = "none" ] || violations+=$'\n'"    $command ($disposition): takes no topic route, found '$topic'"
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: non-public index rows:$violations"
    return 1
  fi
}

@test "case 8: index_only is transitional — no user_invocable surface rests there" {
  local violations="" command disposition flag
  while IFS=$'\t' read -r command _file _topic _audience disposition _rest; do
    [ "$disposition" = "index_only" ] || continue
    flag="${ENUM_FLAG[$command]:-}"
    if [ "$flag" = "true" ]; then
      violations+=$'\n'"    $command is 'user_invocable: true' but parked as index_only — give it a topic and a '### Topic:' section (disposition 'current')"
    fi
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: public surfaces indexed but left unrouted:$violations"
    echo "  index_only is a transitional state for a surface the help rewrite has"
    echo "  not reached yet — it is not a way to declare a command unfindable."
    return 1
  fi
}

@test "case 9: every index row carries all inspected columns" {
  local violations="" command file topic audience disposition final_turn purpose
  while IFS=$'\t' read -r command file topic audience disposition final_turn purpose; do
    for pair in "command=$command" "file=$file" "topic=$topic" \
                "audience=$audience" "disposition=$disposition" \
                "final_turn=$final_turn" "purpose=$purpose"; do
      case "$pair" in
        *=|*=null) violations+=$'\n'"    $command: empty or null column ${pair%%=*}" ;;
      esac
    done
    case "$disposition" in
      current|update|index_only|intentionally_internal|remove_or_deprecate) ;;
      *) violations+=$'\n'"    $command: unknown disposition '$disposition'" ;;
    esac
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: help-index.yaml rows:$violations"
    return 1
  fi
}
