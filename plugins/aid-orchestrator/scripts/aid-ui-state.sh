#!/usr/bin/env bash
# =============================================================================
# aid-ui-state.sh — the only writer of <project>/docs/brand/state.json (/aid-ui).
#
#   init <project>
#   await-direction <project> --imp <impeccable CLI> --key <key> --page-url <url>
#       runs `<imp> serve-question --wait --key <key>` itself (repeats on exit 3).
#       ANSWER {optionId != reroll} -> .aid-ui/direction-answer.json + direction
#       recorded; ANSWER reroll -> exit 3; page closed (exit 4) -> direction_pending
#       + exit 1; anything unparseable -> exit 1, nothing recorded.
#       There is deliberately no verb that records a direction from a file the
#       caller supplies: the answer only ever comes from Impeccable's stdout.
#   pending-direction <project> --key <key> --page-url <url>
#   require-direction <project>
#   set <project> <product_type|refs|impeccable.surface_brief|impeccable.seed_key> <json>
#   step <project> <0-6>                 4-6 refused without a recorded direction
#   roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>
#   chapter <project> <id> <ceka|navrh|schvaleno> [--by <who>]
#   reset-approvals <project> <id>...
#
# Exit: 0 ok, 1 refused, 2 usage. (await-direction: 3 = re-roll requested.)
# =============================================================================
set -euo pipefail

TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/ui-design/brand-page" && pwd)/state.template.json"
CHAPTERS=" produkt logo barvy typografie smer komponenty platformy ukazky schvaleni "
SETTABLE=" product_type refs impeccable.surface_brief impeccable.seed_key "

usage() { echo "ERROR: aid-ui-state.sh: ${1:-usage}; see the header of this script" >&2; exit 2; }
die() { echo "ERROR: aid-ui-state.sh: $1" >&2; exit 1; }
today() { date -u +%Y-%m-%d; }

(( $# >= 2 )) || usage "need <verb> <project>"
VERB="$1"; PROJECT="$2"; shift 2
BRAND="$PROJECT/docs/brand"
STATE="$BRAND/state.json"

need_state() { [[ -f "$STATE" ]] || die "no $STATE; run: aid-ui-state.sh init $PROJECT"; }

# jq_write <jq filter> [jq args...] — atomic rewrite of state.json.
jq_write() {
  local tmp; tmp="$(mktemp "$STATE.XXXXXX")"
  if jq "$@" "$STATE" > "$tmp"; then mv "$tmp" "$STATE"; else rm -f "$tmp"; die "could not write $STATE"; fi
}

opt() {   # opt <name> <args...> — value after --<name>
  local name="$1"; shift
  while (( $# )); do [[ "$1" == "--$name" ]] && { echo "${2:-}"; return; }; shift; done
}

require_direction() {   # prints what is missing, returns 1 when not recorded
  local opt_id file sha pend msg=""
  opt_id="$(jq -r '.direction.option_id // empty' "$STATE")"
  file="$(jq -r '.direction.answer_file // empty' "$STATE")"
  sha="$(jq -r '.direction.answer_sha256 // empty' "$STATE")"
  pend="$(jq -r 'if .direction_pending then "URL \(.direction_pending.page_url) key \(.direction_pending.key)" else empty end' "$STATE")"
  if [[ -z "$opt_id" ]]; then msg="no direction recorded (direction.option_id)"
  elif [[ ! -f "$PROJECT/$file" ]]; then msg="the answer file $file is missing"
  elif [[ "$(sha256sum "$PROJECT/$file" | cut -d' ' -f1)" != "$sha" ]]; then msg="the answer file $file changed since it was recorded"
  fi
  [[ -n "$pend" ]] && msg="${msg:+$msg; }a direction round is open and unanswered: $pend"
  [[ -z "$msg" ]] && return 0
  echo "ERROR: aid-ui-state.sh: $msg. The direction is chosen in step 3 by the PM on Impeccable's page." >&2
  return 1
}

# write_chapter <id> <status> <by> — state.json and index.html together.
write_chapter() {
  local id="$1" status="$2" by="$3" date="" html="$BRAND/index.html"
  [[ "$CHAPTERS" == *" $id "* ]] || usage "unknown chapter id: $id"
  case "$status" in ceka|navrh|schvaleno) ;; *) usage "unknown status: $status" ;; esac
  [[ -f "$html" ]] || die "no $html"
  [[ "$status" == ceka ]] || date="$(today)"
  local tmp; tmp="$(mktemp "$html.XXXXXX")"
  python3 - "$html" "$id" "$status" "$date" "$by" > "$tmp" <<'PY' || { rm -f "$tmp"; die "section $id not found in $html"; }
import html, re, sys
path, cid, status, date, by = sys.argv[1:]
text = open(path, encoding="utf-8").read()
label = " · ".join(html.escape(x) for x in (date, by) if x)
pat = re.compile(r'(<section id="%s" data-status=")[^"]*(">.*?<p class="status">).*?(</p>)' % re.escape(cid), re.S)
new, n = pat.subn(lambda m: m.group(1) + status + m.group(2) + label + m.group(3), text, count=1)
if n != 1:
    sys.exit(1)
sys.stdout.write(new)
PY
  jq_write --arg id "$id" --arg s "$status" --arg d "$date" --arg by "$by" \
    '.chapters[$id] = ({status: $s} + (if $d != "" then {date: $d} else {} end) + (if $by != "" then {by: $by} else {} end))'
  mv "$tmp" "$html"
}

case "$VERB" in
  init)
    mkdir -p "$BRAND"
    if [[ -f "$STATE" ]]; then echo "state.json exists; continuing from step $(jq -r .step "$STATE")"
    else cp "$TEMPLATE" "$STATE"; echo "state.json created: $STATE"; fi
    ;;

  await-direction)
    need_state
    IMP="$(opt imp "$@")"; KEY="$(opt key "$@")"; URL="$(opt page-url "$@")"
    [[ -n "$IMP" && -n "$KEY" && -n "$URL" ]] || usage "await-direction needs --imp --key --page-url"
    while :; do
      rc=0; out="$(IMPECCABLE_QUESTION_FORCE=1 "$IMP" serve-question --wait --key "$KEY")" || rc=$?
      [[ "$rc" -eq 3 ]] || break
    done
    if [[ "$rc" -eq 4 ]]; then
      jq_write --arg k "$KEY" --arg u "$URL" '.direction_pending = {key: $k, page_url: $u}'
      die "the page closed without the PM's answer; the round stays open: URL $URL key $KEY"
    fi
    [[ "$rc" -eq 0 ]] || die "serve-question --wait exited $rc; nothing recorded: $out"
    # Impeccable prints `ANSWER: {json}`; a bare JSON line is accepted too. Last one wins.
    answer="$(sed -n 's/^ANSWER: //; /^{.*}$/p' <<<"$out" | while IFS= read -r l; do
      jq -ec 'select(type == "object" and (.optionId | type) == "string")' <<<"$l" 2>/dev/null || true; done | tail -n1)"
    [[ -n "$answer" ]] || die "no ANSWER with an optionId in Impeccable's output; nothing recorded: $out"
    OPT="$(jq -r .optionId <<<"$answer")"
    if [[ "$OPT" == reroll ]]; then echo "REROLL: $answer"; exit 3; fi
    mkdir -p "$PROJECT/.aid-ui"
    printf '%s\n' "$answer" > "$PROJECT/.aid-ui/direction-answer.json"
    SHA="$(sha256sum "$PROJECT/.aid-ui/direction-answer.json" | cut -d' ' -f1)"
    jq_write --arg o "$OPT" --arg k "$KEY" --arg sha "$SHA" --arg u "$URL" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg d "$(today)" \
      '.direction = {option_id: $o, key: $k, answer_file: ".aid-ui/direction-answer.json", answer_sha256: $sha, answered_at: $at, page_url: $u}
       | del(.direction_pending) | .decisions += [{step: 3, what: "direction \($o)", date: $d}]'
    echo "DIRECTION: $OPT"
    ;;

  pending-direction)
    need_state
    KEY="$(opt key "$@")"; URL="$(opt page-url "$@")"
    [[ -n "$KEY" && -n "$URL" ]] || usage "pending-direction needs --key --page-url"
    jq_write --arg k "$KEY" --arg u "$URL" '.direction_pending = {key: $k, page_url: $u}'
    ;;

  require-direction)
    need_state
    require_direction || exit 1
    echo "direction: $(jq -r .direction.option_id "$STATE")"
    ;;

  set)
    need_state
    (( $# == 2 )) || usage "set needs <key> <json>"
    [[ "$SETTABLE" == *" $1 "* ]] || usage "set cannot write '$1' (only:$SETTABLE)"
    jq -e . >/dev/null 2>&1 <<<"$2" || usage "not JSON: $2"
    jq_write --arg p "$1" --argjson v "$2" 'setpath($p | split("."); $v)'
    ;;

  step)
    need_state
    [[ "${1:-}" =~ ^[0-6]$ ]] || usage "step needs 0-6"
    if (( $1 >= 4 )) && ! require_direction; then die "step $1 refused: run step 3 first (/aid-ui 3)"; fi
    jq_write --argjson n "$1" '.step = $n'
    ;;

  roles)
    need_state
    (( $# == 1 )) || usage "roles needs bg=..,ink=..,accent=..,display=..,body=.."
    tokens="$BRAND/tokens.css"; [[ -f "$tokens" ]] || die "no $tokens"
    declare -A R=()
    IFS=, read -ra pairs <<<"$1"
    for p in "${pairs[@]}"; do
      k="${p%%=*}"; v="${p#*=}"
      [[ " bg ink accent display body " == *" $k "* && "$v" =~ ^[a-z0-9-]+$ ]] || usage "bad role pair: $p"
      R[$k]="$v"
    done
    for k in bg ink accent display body; do [[ -n "${R[$k]:-}" ]] || usage "missing role: $k"; done
    for k in bg ink accent; do grep -q -- "--color-${R[$k]}:" "$tokens" || die "unknown color '${R[$k]}' for $k in $tokens"; done
    for k in display body; do grep -q -- "--font-${R[$k]}-family:" "$tokens" || die "unknown typography role '${R[$k]}' for $k in $tokens"; done
    tmp="$(mktemp "$BRAND/roles.css.XXXXXX")"
    {
      echo "/* Written by aid-ui-state.sh roles; do not edit. */"
      echo ":root {"
      for k in bg ink accent; do echo "  --brand-$k: var(--color-${R[$k]});"; done
      for k in display body; do for f in family size weight line-height letter-spacing; do
        echo "  --brand-$k-$f: var(--font-${R[$k]}-$f);"; done; done
      echo "}"
    } > "$tmp"
    jq_write --arg bg "${R[bg]}" --arg ink "${R[ink]}" --arg ac "${R[accent]}" --arg d "${R[display]}" --arg b "${R[body]}" \
      '.roles = {bg: $bg, ink: $ink, accent: $ac, display: $d, body: $b}'
    mv "$tmp" "$BRAND/roles.css"
    ;;

  chapter)
    need_state
    (( $# == 2 || $# == 4 )) || usage "chapter needs <id> <status> [--by <who>]"
    by=""; (( $# == 4 )) && { [[ "$3" == --by ]] || usage "unknown option $3"; by="$4"; }
    write_chapter "$1" "$2" "$by"
    ;;

  reset-approvals)
    need_state
    (( $# >= 1 )) || usage "reset-approvals needs <id>..."
    for id in "$@"; do [[ "$CHAPTERS" == *" $id "* ]] || usage "unknown chapter id: $id"; done
    for id in "$@"; do
      if [[ "$(jq -r --arg id "$id" '.chapters[$id].status' "$STATE")" == schvaleno ]]; then write_chapter "$id" navrh ""; fi
    done
    ;;

  *) usage "unknown verb: $VERB" ;;
esac
