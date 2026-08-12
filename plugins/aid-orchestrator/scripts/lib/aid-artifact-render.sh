#!/usr/bin/env bash
# aid-artifact-render.sh — P080 Step 10.
#
# Fills the ecosystem artifact skeleton DETERMINISTICALLY and emits an artifact
# BODY. Sourceable; one entry point:
#
#   aid_artifact_render <template_id> <facts_json> <prose_json> <out_path>
#
#   template_id  resolves to defaults/templates/artifact-<id>.html ("outcome").
#   facts_json   file path OR literal JSON. Everything COMPUTED by the caller
#                from canonical JSON: tiles, lists, links, detail target.
#   prose_json   file path OR literal JSON. The bounded model-written blocks
#                (summary / core / ask). May be missing — see below.
#   out_path     the file the body is written to.
#
# WHAT THIS IS NOT
#   It does not publish. It does not read run state. It is a pure function of
#   its two JSON inputs plus the template — testable with fixtures, reusable by
#   every renderer built on top of it. Publication (the Artifact tool) belongs
#   to the controller instruction, mirroring aid-test-audit-chat-summary.sh's
#   Artifact-first banner precedent.
#
#   The output is a BODY: no <!doctype>, no <html>/<head>/<body> tag. The
#   Artifact tool supplies the skeleton and a CSP blocks every external asset,
#   so all CSS is inline and nothing may be fetched.
#
# MANDATORY VERSUS CONDITIONAL — as the standard defines it, not tighter
#   Blocks 1-4 and 6 ALWAYS render. Block 6 in particular is never omitted: an
#   input that asks for nothing renders _AID_ARTIFACT_ASK_NOTHING, because a
#   silently absent ask block reads as "nothing is required of me".
#   Block 5 renders only when links exist. Block 7 renders only when a detail
#   target is an EXPLICIT input — this library never infers one. A caller that
#   always has a detail target states and tests that for itself.
#
# BREVITY IS ENFORCED HERE, IN CODE, NOT ASKED FOR IN PROSE
#   _AID_ARTIFACT_CAP_ITEMS      5   result items
#   _AID_ARTIFACT_CAP_NEXT       3   "jak pokračovat" steps
#   _AID_ARTIFACT_CAP_LINKS      5   related links
#   _AID_ARTIFACT_CAP_SENTENCE 220   chars per sentence
#   _AID_ARTIFACT_CAP_SUMMARY  320   chars for prose.summary
#   _AID_ARTIFACT_CAP_CORE     300   chars for prose.core
#   _AID_ARTIFACT_CAP_ASK      220   chars for prose.ask
#   Overflow is never silent: it emits _AID_ARTIFACT_OVERFLOW_FMT carrying the
#   TRUE remaining count.
#
# FIXED LITERALS — declared once, here, so a test can grep an exact string
#   _AID_ARTIFACT_ASK_NOTHING    "Nic — ozvu se, až bude hotovo"
#   _AID_ARTIFACT_PROSE_MISSING  "Shrnutí chybí — čísla výše jsou dopočítaná a platí."
#   _AID_ARTIFACT_OVERFLOW_FMT   "a dalších N v technickém detailu"
#   _AID_ARTIFACT_ABSENT         "—"
#   One literal per state. No "or its English equivalent".
#
# SECRET POLICY AT THE RENDERER BOUNDARY — redact, count, never fail closed
#   The ecosystem artifact standard forbids passwords, tokens, keys or
#   FRAGMENTS of them in any artifact. Gate `output` fields carry arbitrary
#   command output straight from a run, so escaping alone is not a policy.
#   Every input this library renders — facts_json, prose_json, and any command
#   output embedded in them — is scanned before a byte is written.
#
#   Matches are REDACTED (<redacted:NAME>), not failed on: failing closed at
#   the gate-outcome boundary would suppress precisely the message telling the
#   PM a run broke. But the redaction is COUNTED and the count is rendered in
#   the provenance footer, so a redaction can never be silent.
#
#   Shipped detectors (name → what it catches):
#     github_token      ghp_/gho_/ghu_/ghs_/ghr_ prefixed tokens
#     github_pat        github_pat_… fine-grained PATs
#     openai_key        sk-… API keys
#     aws_access_key    AKIA… access key ids
#     pem_private_key   -----BEGIN … PRIVATE KEY-----
#     bearer_token      Bearer <token>
#     assigned_secret   password=/token=/api_key=/apikey=/secret= assignments
#     high_entropy_blob long base64/hex runs
#   `/` is deliberately excluded from high_entropy_blob so long filesystem
#   paths — legitimate content in an INTERNAL artifact — are not shredded.
#
#   Escaping is applied AFTER redaction, never instead of it.
#
# ERROR HANDLING
#   invalid facts_json  → exit 1 with the jq error. An artifact carrying wrong
#                         numbers is worse than no artifact.
#   invalid/missing prose_json → render anyway, with the alarm block saying the
#                         summary is missing. A half-empty page must SAY so.
#   unwritable out_path → exit 3.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_AID_ARTIFACT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_ARTIFACT_TEMPLATE_DIR="${_AID_ARTIFACT_LIB_DIR}/../../defaults/templates"

_AID_ARTIFACT_CAP_ITEMS=5
_AID_ARTIFACT_CAP_NEXT=3
_AID_ARTIFACT_CAP_LINKS=5
_AID_ARTIFACT_CAP_SENTENCE=220
_AID_ARTIFACT_CAP_SUMMARY=320
_AID_ARTIFACT_CAP_CORE=300
_AID_ARTIFACT_CAP_ASK=220

_AID_ARTIFACT_ABSENT="—"
_AID_ARTIFACT_ASK_NOTHING="Nic — ozvu se, až bude hotovo"
_AID_ARTIFACT_PROSE_MISSING="Shrnutí chybí — čísla výše jsou dopočítaná a platí."

# _aid_artifact_overflow <remaining> — the one overflow sentence.
_aid_artifact_overflow() {
  printf 'a dalších %s v technickém detailu' "$1"
}

# The detector table. `name|ERE`. Order matters: specific detectors run before
# the catch-all entropy run, so a token is named rather than blurred.
_AID_ARTIFACT_DETECTORS=(
  'github_pat|github_pat_[A-Za-z0-9_]{20,}'
  'github_token|gh[pousr]_[A-Za-z0-9]{16,}'
  'openai_key|sk-[A-Za-z0-9_-]{16,}'
  'aws_access_key|AKIA[0-9A-Z]{16}'
  'pem_private_key|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'bearer_token|Bearer [A-Za-z0-9._~+=-]{16,}'
  'assigned_secret|(password|passwd|token|api_key|apikey|secret)=[^[:space:]"'"'"',]{6,}'
  'high_entropy_blob|[A-Za-z0-9+]{40,}={0,2}'
)

# _aid_artifact_redact <text_var_name> <count_var_name>
#   Redacts IN PLACE and adds the match count to the counter variable.
#   Deliberately NOT `text=$(_aid_artifact_redact "$text")`: a command
#   substitution is a subshell, so a count set inside one never reaches the
#   caller and every artifact would have reported "Redigováno: 0".
#
#   `/` is the sed delimiter below — no shipped detector pattern and no
#   replacement contains one. A future detector that does must change it.
#   `grep -e` is likewise load-bearing: pem_private_key starts with `-`.
_aid_artifact_redact() {
  local -n _rd_text="$1"
  local -n _rd_count="$2"
  local entry name re hits
  for entry in "${_AID_ARTIFACT_DETECTORS[@]}"; do
    name="${entry%%|*}"
    re="${entry#*|}"
    hits="$(printf '%s' "$_rd_text" | { grep -oE -e "$re" || true; } | wc -l)"
    [[ "$hits" =~ ^[0-9]+$ ]] || hits=0
    if (( hits > 0 )); then
      _rd_count=$(( _rd_count + hits ))
      _rd_text="$(printf '%s' "$_rd_text" | sed -E "s/${re}/<redacted:${name}>/g")"
    fi
  done
}

# _aid_artifact_escape <text> — every value interpolated from input goes
# through this, AFTER redaction.
#
# The `\&` are load-bearing: since bash 5.2 an unescaped `&` in a ${x//p/r}
# replacement means "the text that matched", so `${s//</&lt;}` produced `<lt;`
# and a title containing < came out of here still unescaped.
_aid_artifact_escape() {
  local s="$1"
  s="${s//&/\&amp;}"
  s="${s//</\&lt;}"
  s="${s//>/\&gt;}"
  s="${s//\"/\&quot;}"
  s="${s//\'/\&#39;}"
  printf '%s' "$s"
}

# _aid_artifact_clip <text> <cap> — collapse whitespace, then truncate at a
# word boundary with an ellipsis. Never mid-word, never silently.
_aid_artifact_clip() {
  local text cap="$2"
  text="$(printf '%s' "$1" | tr '\n\t' '  ' | tr -s ' ')"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  if (( ${#text} <= cap )); then
    printf '%s' "$text"
    return 0
  fi
  local head="${text:0:cap-1}"
  if [[ "$head" == *" "* ]]; then head="${head% *}"; fi
  printf '%s…' "$head"
}

# _aid_artifact_cap_sentences <text> — the ~220-chars-per-sentence rule from
# the standard, applied sentence by sentence so one runaway clause does not
# take the whole block with it.
_aid_artifact_cap_sentences() {
  # NOT `local text="$1" rest="$text"` — a name is not yet visible to a later
  # assignment in the same `local`, so under `set -u` that aborted the whole
  # render and every prose block came out empty.
  local out="" sentence
  local rest="$1"
  while [[ "$rest" == *". "* ]]; do
    sentence="${rest%%. *}"
    rest="${rest#*". "}"
    out+="$(_aid_artifact_clip "$sentence" "$_AID_ARTIFACT_CAP_SENTENCE"). "
  done
  out+="$(_aid_artifact_clip "$rest" "$_AID_ARTIFACT_CAP_SENTENCE")"
  printf '%s' "$out"
}

# _aid_artifact_list <json_array> <cap> <ordered:0|1>
#   The capped, escaped list plus the explicit overflow line. The count in that
#   line is the TRUE remaining count, computed here — never claimed by a
#   caller's prose.
_aid_artifact_list() {
  local arr="$1" cap="$2" ordered="${3:-0}"
  local total shown="" i item tag="ul" cls=""
  total="$(jq -r 'length' <<<"$arr" 2>/dev/null)" || total=0
  [[ "$total" =~ ^[0-9]+$ ]] || total=0
  (( total > 0 )) || { printf ''; return 0; }
  if [[ "$ordered" == "1" ]]; then tag="ol"; cls=" class=\"steps\""; fi
  for (( i = 0; i < total && i < cap; i++ )); do
    item="$(jq -r --argjson i "$i" '.[$i] | if type == "object" then (.name // .label // (.|tostring)) else tostring end' <<<"$arr")"
    item="$(_aid_artifact_cap_sentences "$item")"
    item="$(_aid_artifact_clip "$item" "$_AID_ARTIFACT_CAP_SENTENCE")"
    shown+="<li>$(_aid_artifact_escape "$item")</li>"
  done
  local out="<${tag}${cls}>${shown}</${tag}>"
  if (( total > cap )); then
    out+="<p class=\"more\">$(_aid_artifact_escape "$(_aid_artifact_overflow "$(( total - cap ))")")</p>"
  fi
  printf '%s' "$out"
}

# _aid_artifact_tile_class <state> — whitelist. An unknown state is dropped to
# the plain tile rather than emitting an attacker-chosen class name.
_aid_artifact_tile_class() {
  case "$1" in
    ok|warn|critical) printf 'tile state-%s' "$1" ;;
    *) printf 'tile' ;;
  esac
}

# _aid_artifact_region <template_var_name> <region> <keep:0|1>
#   Keeps a conditional region (stripping its markers) or removes it whole.
_aid_artifact_region() {
  local -n _tpl="$1"
  local region="$2" keep="$3"
  local open="<!--IF:${region}-->" close="<!--ENDIF:${region}-->"
  while [[ "$_tpl" == *"$open"* && "$_tpl" == *"$close"* ]]; do
    local before="${_tpl%%"$open"*}"
    local after_open="${_tpl#*"$open"}"
    local inner="${after_open%%"$close"*}"
    local after="${after_open#*"$close"}"
    if [[ "$keep" == "1" ]]; then
      _tpl="${before}${inner}${after}"
    else
      _tpl="${before}${after}"
    fi
  done
}

# aid_artifact_render <template_id> <facts_json> <prose_json> <out_path>
aid_artifact_render() {
  local template_id="${1-}" facts_in="${2-}" prose_in="${3-}" out_path="${4-}"

  if [[ -z "$template_id" || -z "$out_path" ]]; then
    echo "aid_artifact_render: usage: aid_artifact_render <template_id> <facts_json> <prose_json> <out_path>" >&2
    return 1
  fi

  local template_path="${_AID_ARTIFACT_TEMPLATE_DIR}/artifact-${template_id}.html"
  if [[ ! -f "$template_path" ]]; then
    echo "aid_artifact_render: unknown template '${template_id}' (no ${template_path})" >&2
    return 1
  fi

  # ── inputs ────────────────────────────────────────────────────────────────
  local facts_raw prose_raw
  if [[ -f "$facts_in" ]]; then facts_raw="$(cat "$facts_in")"; else facts_raw="$facts_in"; fi
  if [[ -n "$prose_in" && -f "$prose_in" ]]; then prose_raw="$(cat "$prose_in")"; else prose_raw="$prose_in"; fi

  # Facts fail CLOSED — an artifact with wrong numbers is worse than none.
  local facts_err
  if ! facts_err="$(jq -e '.' <<<"$facts_raw" 2>&1 >/dev/null)"; then
    echo "aid_artifact_render: invalid facts_json: ${facts_err}" >&2
    return 1
  fi

  # ── redaction, before a byte is written, over BOTH inputs together so the
  #    footer count covers everything this page carries ───────────────────────
  local redactions=0
  _aid_artifact_redact facts_raw redactions
  [[ -z "$prose_raw" ]] || _aid_artifact_redact prose_raw redactions

  # Redaction must not have broken the facts document. If it did, that is a
  # fail-closed case: we cannot vouch for the numbers any more.
  if ! jq -e '.' <<<"$facts_raw" >/dev/null 2>&1; then
    echo "aid_artifact_render: facts_json is no longer valid after redaction — refusing to render" >&2
    return 1
  fi

  # Prose fails OPEN, with the page SAYING the summary is missing.
  local prose_ok="true"
  if [[ -z "$prose_raw" ]] || ! jq -e '.' <<<"$prose_raw" >/dev/null 2>&1; then
    prose_ok="false"
    prose_raw='{}'
  fi

  # ── computed facts: tile classes and the redaction count ──────────────────
  local st_result st_duration st_scope st_unresolved
  st_result="$(jq -r '.tiles.result.state // "" | tostring' <<<"$facts_raw")"
  st_duration="$(jq -r '.tiles.duration.state // "" | tostring' <<<"$facts_raw")"
  st_scope="$(jq -r '.tiles.scope.state // "" | tostring' <<<"$facts_raw")"
  st_unresolved="$(jq -r '.tiles.unresolved.state // "" | tostring' <<<"$facts_raw")"

  facts_raw="$(jq \
    --arg rc "$(_aid_artifact_tile_class "$st_result")" \
    --arg dc "$(_aid_artifact_tile_class "$st_duration")" \
    --arg sc "$(_aid_artifact_tile_class "$st_scope")" \
    --arg uc "$(_aid_artifact_tile_class "$st_unresolved")" \
    --arg red "$redactions" \
    '.computed = {result_class:$rc, duration_class:$dc, scope_class:$sc, unresolved_class:$uc, redactions_total:$red}
     | .tiles.result.label      //= "Výsledek"
     | .tiles.duration.label    //= "Trvalo"
     | .tiles.scope.label       //= "Rozsah"
     | .tiles.unresolved.label  //= "Neuzavřeno"' <<<"$facts_raw")" || {
    echo "aid_artifact_render: failed to compute derived facts" >&2
    return 1
  }

  # ── library-built fragments (the {{html:*}} grammar) ──────────────────────
  local items_arr next_arr links_arr
  items_arr="$(jq -c '(.items // []) | if type == "array" then . else [] end' <<<"$facts_raw")"
  next_arr="$(jq -c '(.next_steps // []) | if type == "array" then . else [] end' <<<"$facts_raw")"
  links_arr="$(jq -c '(.links // []) | if type == "array" then . else [] end' <<<"$facts_raw")"

  local html_items html_next html_links
  html_items="$(_aid_artifact_list "$items_arr" "$_AID_ARTIFACT_CAP_ITEMS" 0)"
  html_next="$(_aid_artifact_list "$next_arr" "$_AID_ARTIFACT_CAP_NEXT" 1)"
  html_links="$(_aid_artifact_list "$links_arr" "$_AID_ARTIFACT_CAP_LINKS" 0)"

  # Block 7 — EXPLICIT input only. No detail label, no block. An href is
  # honoured only when it is same-document/relative: the artifact CSP contract
  # forbids an external target, so an absolute one degrades to the target
  # NAMED as text rather than silently linking off-origin.
  local detail_label detail_href html_detail="" have_detail=0
  detail_label="$(jq -r '.detail.label // .detail.name // "" | tostring' <<<"$facts_raw")"
  detail_href="$(jq -r '.detail.href // "" | tostring' <<<"$facts_raw")"
  if [[ -n "$detail_label" ]]; then
    have_detail=1
    detail_label="$(_aid_artifact_clip "$detail_label" "$_AID_ARTIFACT_CAP_SENTENCE")"
    # The scheme test runs on a WHITESPACE-STRIPPED probe, never on the raw
    # value: browsers trim leading/trailing ASCII whitespace and strip tab/CR/LF
    # from anywhere in an href before resolving it, so " javascript:alert(1)"
    # and "j<TAB>avascript:…" are executable schemes wearing a space. Anchoring
    # the regex at the raw string let both through as "relative". The probe only
    # ever DECIDES; the attribute still carries the original, escaped value.
    local href_probe="${detail_href//[$' \t\r\n\f\v']/}"
    if [[ -n "$href_probe" && ! "$href_probe" =~ ^[A-Za-z][A-Za-z0-9+.-]*: && ! "$href_probe" =~ ^// ]]; then
      html_detail="<a class=\"golink\" href=\"$(_aid_artifact_escape "$detail_href")\">$(_aid_artifact_escape "$detail_label") →</a>"
    else
      html_detail="<div class=\"golink\">$(_aid_artifact_escape "$detail_label") →</div>"
    fi
  fi

  # ── prose blocks: sentence cap, then block cap, then escape ───────────────
  local p_summary p_core p_ask
  p_summary="$(jq -r '.summary // "" | tostring' <<<"$prose_raw")"
  p_core="$(jq -r '.core // "" | tostring' <<<"$prose_raw")"
  p_ask="$(jq -r '.ask // "" | tostring' <<<"$prose_raw")"

  local summary_missing=0
  if [[ -z "${p_summary// /}" ]]; then p_summary="$_AID_ARTIFACT_PROSE_MISSING"; summary_missing=1; fi
  if [[ -z "${p_core// /}" ]]; then p_core="$_AID_ARTIFACT_PROSE_MISSING"; summary_missing=1; fi
  # Block 6 NEVER disappears. Nothing asked for is itself the answer.
  if [[ -z "${p_ask// /}" ]]; then p_ask="$_AID_ARTIFACT_ASK_NOTHING"; fi
  [[ "$prose_ok" == "true" ]] || summary_missing=1

  p_summary="$(_aid_artifact_clip "$(_aid_artifact_cap_sentences "$p_summary")" "$_AID_ARTIFACT_CAP_SUMMARY")"
  p_core="$(_aid_artifact_clip "$(_aid_artifact_cap_sentences "$p_core")" "$_AID_ARTIFACT_CAP_CORE")"
  p_ask="$(_aid_artifact_clip "$(_aid_artifact_cap_sentences "$p_ask")" "$_AID_ARTIFACT_CAP_ASK")"

  # ── template: regions first, then a SINGLE substitution pass ──────────────
  local tpl
  tpl="$(cat "$template_path")" || { echo "aid_artifact_render: cannot read ${template_path}" >&2; return 1; }

  # The template's leading comment is contributor documentation, not page
  # content — and it names the very <html>/<head>/<body> tags the body is
  # forbidden to carry. The body starts at <style>; everything above it goes.
  #
  # The match is LINE-ANCHORED, and both simpler forms were wrong:
  #   ${tpl#*-->}      — the header documents the <!--IF:name--> markers, so the
  #                      first `-->` sits inside the comment.
  #   ${tpl#*<style>}  — the header also mentions <style> in a sentence.
  # Both left a paragraph of documentation prose at the top of every page.
  tpl="$(sed -n '/^<style>$/,$p' <<<"$tpl")"
  [[ -n "$tpl" ]] || { echo "aid_artifact_render: ${template_path} has no <style> line" >&2; return 1; }

  _aid_artifact_region tpl prose_missing "$([[ "$summary_missing" == "1" ]] && echo 1 || echo 0)"
  _aid_artifact_region tpl items         "$([[ -n "$html_items" ]] && echo 1 || echo 0)"
  _aid_artifact_region tpl next_steps    "$([[ -n "$html_next" ]] && echo 1 || echo 0)"
  _aid_artifact_region tpl links         "$([[ -n "$html_links" ]] && echo 1 || echo 0)"
  _aid_artifact_region tpl detail        "$have_detail"

  local out="" rest="$tpl" match kind key value
  while [[ "$rest" =~ \{\{(fact|prose|html):([A-Za-z0-9_.]+)\}\} ]]; do
    match="${BASH_REMATCH[0]}"
    kind="${BASH_REMATCH[1]}"
    key="${BASH_REMATCH[2]}"
    out+="${rest%%"$match"*}"
    rest="${rest#*"$match"}"
    case "$kind" in
      fact)
        value="$(jq -r --arg k "$key" '
          reduce ($k | split(".")[]) as $p (.; if type == "object" then .[$p] else null end)
          | if . == null or . == "" then "—" else tostring end' <<<"$facts_raw" 2>/dev/null)"
        [[ -n "$value" ]] || value="$_AID_ARTIFACT_ABSENT"
        value="$(_aid_artifact_escape "$value")"
        ;;
      prose)
        case "$key" in
          summary) value="$(_aid_artifact_escape "$p_summary")" ;;
          core)    value="$(_aid_artifact_escape "$p_core")" ;;
          ask)     value="$(_aid_artifact_escape "$p_ask")" ;;
          *)       value="$_AID_ARTIFACT_ABSENT" ;;
        esac
        ;;
      html)
        # The only raw-markup grammar, and it is unreachable from input: every
        # fragment below was built and escaped above.
        case "$key" in
          items)                 value="$html_items" ;;
          next_steps)            value="$html_next" ;;
          links)                 value="$html_links" ;;
          detail)                value="$html_detail" ;;
          prose_missing_notice)  value="$(_aid_artifact_escape "$_AID_ARTIFACT_PROSE_MISSING")" ;;
          *)                     value="" ;;
        esac
        ;;
    esac
    # Appended AFTER `rest` was advanced past the match: a value containing
    # {{ is therefore never re-expanded. Single pass, by construction.
    out+="$value"
  done
  out+="$rest"

  # The write is ATOMIC: a temp file in the TARGET directory (so the rename is
  # same-filesystem, hence atomic), then `mv`. A direct `> "$out_path"` looks
  # equivalent right up to the moment the write dies mid-stream — a full disk,
  # a quota, an `ulimit -f` cap — and then it leaves a TRUNCATED page sitting at
  # the published path while this function returns 3. A half-written artifact
  # that still looks like a page is precisely what the fail-closed contract
  # above exists to prevent, so out_path is never opened for writing at all.
  #
  # THE RENAME REPLACES THE INODE, SO IT MUST CARRY THE MODE ACROSS. `mktemp`
  # creates 0600 and `mv` puts that inode at the published path, so re-rendering
  # an existing 0640 artifact silently demoted it to 0600 and locked out the group
  # reader (or the web server) that was reading the previous page. When the
  # destination exists its mode is copied onto the temp file BEFORE the rename;
  # when it does not, the umask decides, as a plain `>` redirection would.
  #
  # A WRITE KILLED BY A SIGNAL CANNOT CLEAN UP AFTER ITSELF unless the signal is
  # caught. `ulimit -f` delivers SIGXFSZ, whose default action terminates the
  # shell mid-`printf` — the cleanup branch below never ran and a partial
  # `.tmp.XXXXXX` was left in the output directory (fail-closed at out_path, but
  # littering beside it). SIGXFSZ is therefore trapped for the duration of the
  # write and restored afterwards, so the cleanup branch is reached and the temp
  # file is removed. A SIGKILL still cannot be cleaned up by anyone; that is the
  # honest limit of this guarantee.
  local out_dir; out_dir="$(dirname "$out_path")"
  local tmp_out=""
  if [[ ! -d "$out_dir" ]] || ! tmp_out="$(mktemp "${out_path}.tmp.XXXXXX" 2>/dev/null)"; then
    echo "aid_artifact_render: cannot write ${out_path}" >&2
    return 3
  fi
  if [[ -e "$out_path" ]]; then
    _aid_artifact_copy_mode "$out_path" "$tmp_out"
  else
    # A FIRST render has no destination mode to inherit, and mktemp's 0600 is
    # not the mode a plain `>` would have produced either. The umask decides, so
    # a newly rendered page is as readable as every other file the run writes.
    chmod "$(printf '%04o' "$(( 0666 & ~0$(umask) ))")" "$tmp_out" 2>/dev/null || true
  fi

  local _prev_xfsz _xfsz_hit=0
  _prev_xfsz="$(trap -p XFSZ)"
  trap '_xfsz_hit=1' XFSZ
  local _write_ok=1
  printf '%s\n' "$out" > "$tmp_out" 2>/dev/null || _write_ok=0
  if [[ -n "$_prev_xfsz" ]]; then eval "$_prev_xfsz"; else trap - XFSZ; fi

  if (( _write_ok == 0 )) || (( _xfsz_hit == 1 )) || ! mv -f "$tmp_out" "$out_path" 2>/dev/null; then
    rm -f "$tmp_out" 2>/dev/null
    echo "aid_artifact_render: cannot write ${out_path}" >&2
    return 3
  fi
  return 0
}

# _aid_artifact_copy_mode <from> <to> — best effort, never fatal under `set -e`.
# GNU `chmod --reference` first; the stat/chmod pair is the BSD fallback.
_aid_artifact_copy_mode() {
  local from="$1" to="$2" mode=""
  chmod --reference="$from" "$to" 2>/dev/null && return 0
  mode="$(stat -c '%a' "$from" 2>/dev/null || stat -f '%Lp' "$from" 2>/dev/null || true)"
  [[ -n "$mode" ]] && chmod "$mode" "$to" 2>/dev/null
  return 0
}
