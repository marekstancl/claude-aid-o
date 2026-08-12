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
# Provenance: plan P080, EPIC E-080-1_3 Step 2; cases 10-11 (the `final_turn`
# output-contract inventory) added by Step 14.

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

# A slash command as a WHOLE WORD. `/aid-audit` must not be matched inside
# `/aid-audit-tests`: AID command names are prefixes of one another, so a plain
# substring test would report the shorter command as routed by a section that only
# ever names the longer one. The trailing guard is "not followed by a word char or a
# hyphen"; the leading guard is "not preceded by a word char or a hyphen", which keeps
# a match at start-of-line working while rejecting `x/aid-do`.
command_word_re() { printf '(^|[^[:alnum:]_-])%s([^[:alnum:]_-]|$)' "$1"; }

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
# heading to the next outside-fence `### ` OR `## ` heading, or EOF, with fenced
# content blanked out. Case 3 matches against THIS: a command named only inside a
# code fence has not been routed to, it has been mentioned.
#
# Ending on `## ` as well as `### ` matters: with only `### ` the LAST topic ran
# to EOF and swallowed every trailing `## ` block. Measured on the shipped file,
# that made /aid-init, /aid-setup and /aid-do count as "routed by topic fsm"
# purely because they are named in the closing sections. Nothing is falsely
# routed today — those three have their own topics — but the hole was sitting
# there waiting for a command whose topic happened to be last.
section_body_unfenced() {
  awk -v want="$1" '
    /^[[:space:]]*```/ { infence = !infence; if (inside) print ""; next }
    !infence && /^#### / { if (inside) print; next }
    !infence && /^### / {
      if ($0 == "### Topic: " want) { inside = 1; next }
      else if (inside) { exit }
    }
    !infence && /^## / { if (inside) exit }
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

@test "an unreadable command file fails the enumeration instead of vanishing from it" {
  # The scan ran inside a process substitution, so the awk pass's fatal error on
  # an unreadable file reached nobody: EVERY command disappeared from the
  # enumeration and the function still returned 0. A silent hole in the
  # inventory is precisely what this suite exists to make impossible, so the
  # missing surface must become a hard failure with a reason.
  if [ "$(id -u)" -eq 0 ]; then skip "running as root — chmod 000 does not deny reads"; fi

  local root="$BATS_TEST_TMPDIR/plugin-root"
  mkdir -p "$root/commands" "$root/skills/demo"
  printf -- '---\nuser_invocable: true\n---\n' > "$root/commands/public.md"
  printf -- '---\nuser_invocable: true\n---\n' > "$root/commands/other.md"
  printf -- '---\nname: demo\n---\n'           > "$root/skills/demo/SKILL.md"

  # Sanity: both commands enumerate while everything is readable.
  run aid_help_enumerate_surfaces "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/public"* ]]

  chmod 000 "$root/commands/public.md"
  run aid_help_enumerate_surfaces "$root"
  chmod 644 "$root/commands/public.md"

  [ "$status" -eq 1 ]
  [[ "$output" == *"frontmatter scan failed"* ]]
  # And it did NOT quietly report the surviving surfaces as the whole inventory.
  [[ "$output" != *"/other	commands/other.md"* ]]
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
    # Word-boundary match, NOT a substring: `/aid-audit` must not be satisfied by a
    # section that only ever names `/aid-audit-tests`. Every AID command is a prefix
    # of some other command or could become one, so a substring match would silently
    # declare the shorter one routed — in the exact assertion this suite exists for.
    if ! grep -qE -- "$(command_word_re "$command")" <<<"$body"; then
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
    if grep -qE -- "$(command_word_re "$command")" <<<"$stripped"; then
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
    # `__late__` counts here too. It means the surface DOES declare a flag, just
    # past the scan window — so parking it at index_only is the same cheap dodge
    # this case exists to kill, and skipping it would leave the hole one step
    # further along.
    if [ "$flag" = "true" ]; then
      violations+=$'\n'"    $command is 'user_invocable: true' but parked as index_only — give it a topic and a '### Topic:' section (disposition 'current')"
    elif [ "$flag" = "__late__" ]; then
      violations+=$'\n'"    $command declares user_invocable past the frontmatter scan window AND is parked as index_only — move the flag into the first ${AID_HELP_COMMAND_FM_LINES:-6} lines, then give it a topic and a '### Topic:' section"
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
  local violations="" command file topic audience disposition final_turn purpose writes
  while IFS=$'\t' read -r command file topic audience disposition final_turn purpose writes; do
    # `writes` is the eighth required column and until now nothing read it: it
    # could be deleted from ten of thirteen rows with the whole suite still green.
    # Step 5 writes the init/setup ownership decisions into exactly this column,
    # so an unchecked column is an unchecked deliverable. `!!null` means the key is
    # absent; `[]` (read-only) and a count are both legitimate.
    # Assert the TYPE, not merely "not null". Checking only for `!!null` accepted
    # `writes: ""`, `writes: "read-only"`, `writes: {}` and `writes: 5` — every one
    # of which reads as a filled-in column while carrying no list of files at all.
    # The column's whole purpose is to name what a surface may write; a scalar
    # there is a claim with no content.
    [ "$writes" = "!!seq" ] || violations+=$'\n'"    $command: column 'writes' must be a list (got ${writes:-<empty>}; use [] for a read-only surface)"
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

@test "case 10: final_turn is a well-formed output-contract entry" {
  # THE §14 D17 INVENTORY RULE, made mechanical. `skills/communication.md` says a
  # path absent from the output-contract inventory cannot quietly emit a final
  # technical dump — which only bites if the inventory is checked. Case 9 proves
  # the column is merely non-empty; a value of `soon` would satisfy it. This case
  # reads the VALUE: its form, its card vocabulary, and the public/internal split.
  #
  # HONEST SCOPE: for `card:` rows this is vocabulary + disposition consistency,
  # not proof the surface emits that card at runtime — observing a real final turn
  # needs a capture harness this plan does not build. `renderer:` rows ARE content-
  # checked, in case 11.
  local violations="" command final_turn disposition card
  while IFS=$'\t' read -r command _file _topic _audience disposition final_turn _rest; do
    if [ -z "$final_turn" ] || [ "$final_turn" = "null" ]; then
      # Public rows especially: an unindexed final turn is exactly the "quietly
      # emits a dump" case. Reported for every row — no surface is exempt.
      violations+=$'\n'"    $command: no final_turn — every row states its final turn as renderer:<script>, card:<type> or internal"
      continue
    fi
    case "$final_turn" in
      renderer:?*) ;;   # content asserted by case 11
      internal)
        # `internal` is the one value that says "this surface never faces the PM".
        # Legal only where the index ALSO says the surface is not user-reachable;
        # otherwise it is the cheapest way to exempt a real command from the
        # inventory, which is the hole the inventory exists to close.
        [ "$disposition" = "intentionally_internal" ] || \
          violations+=$'\n'"    $command: final_turn 'internal' but disposition is '$disposition' — a user-reachable surface owes the PM a card"
        ;;
      card:?*)
        card="${final_turn#card:}"
        case "$card" in
          finished|decision-required|blocked|progress) ;;
          *) violations+=$'\n'"    $command: unknown card type '$card' — skills/communication.md defines four: finished, decision-required, blocked, progress" ;;
        esac
        ;;
      *)
        violations+=$'\n'"    $command: malformed final_turn '$final_turn' — expected renderer:<script>, card:<type> or internal"
        ;;
    esac
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: help-index.yaml final_turn column:$violations"
    return 1
  fi
}

@test "case 11: every final_turn renderer exists and is wired into its own surface" {
  # The half that checks CONTENT, not shape. Two ways a `renderer:` value lies:
  # it can name a script that does not exist (a rename, a deleted library), or it
  # can name a real script the surface never sources — an inventory entry with no
  # mechanism behind it, which is this plan's recurring defect wearing a filename.
  # Both fail here. The wiring match is on the BASENAME because surfaces cite the
  # library at whatever depth reads naturally (`lib/x.sh`, `scripts/lib/x.sh`).
  local violations="" command file final_turn script base
  while IFS=$'\t' read -r command file _topic _audience _disposition final_turn _rest; do
    case "$final_turn" in renderer:?*) ;; *) continue ;; esac
    script="${final_turn#renderer:}"
    base="${script##*/}"

    if [ ! -f "$AID_PLUGIN_PATH/$script" ]; then
      violations+=$'\n'"    $command: final_turn names a renderer that does not exist: $script"
      continue
    fi
    if [ ! -f "$REPO_ROOT/$file" ]; then
      continue   # case 6 owns the missing-file report
    fi
    if ! grep -qF -- "$base" "$REPO_ROOT/$file"; then
      violations+=$'\n'"    $command: final_turn names $script but $file never mentions $base — the row claims a renderer the surface does not wire"
    fi
  done < <(index_rows)

  if [ -n "$violations" ]; then
    echo "FAIL: help-index.yaml renderer wiring:$violations"
    return 1
  fi
}
