#!/usr/bin/env bash
# =============================================================================
# aid-render-prompt.sh — deterministic, JSON-aware prompt-template renderer
# (P065, E-065-1_7, Step 4)
#
# Renders a versioned prompt template (e.g. defaults/prompts/review-prompt-v1.md)
# into a concrete prompt by substituting `{{variable}}` placeholders with values
# from a canonical JSON object. The template is a COMMITTED contract; this
# renderer is the ONLY sanctioned way to fill it, so the Codex prompt is never
# improvised in a shell heredoc at dispatch time.
#
# ---------------------------------------------------------------------------
# Interface (PINNED — do not change without a new EPIC):
#   aid-render-prompt.sh --template <file> --vars-json <canonical-json-file> \
#                        --output <file>
# ---------------------------------------------------------------------------
#
# Contract (fails CLOSED — any violation → exit 1, no --output written):
#   * <file> template carries YAML frontmatter with `variables: [...]` — that
#     list is the AUTHORITATIVE declared variable set.
#   * --vars-json is a canonical JSON OBJECT whose key set EXACTLY equals the
#     declared set (any missing OR unknown key fails).
#   * Every value in --vars-json is a STRING (non-string fails) and MUST NOT
#     itself contain the placeholder opener `{{` (injection guard; keeps
#     substitution order-independent and prevents value→placeholder bleed).
#   * Every `{{...}}` placeholder in the template body MUST be a declared
#     variable (an undeclared body placeholder fails).
#   * Substitution is a JSON-AWARE literal pass via jq split/join — NEVER via
#     `eval`, `sed` interpolation, or shell string assembly.
#   * If ANY `{{...}}` remains after substitution, that fails (belt + braces).
#
# On success:
#   * writes the rendered prompt to --output (byte-exact template + substitutions,
#     via `jq -j` so no spurious trailing newline is added);
#   * prints a provenance JSON object to STDOUT (chosen over a sidecar file so
#     the caller controls where/if it is persisted for the manifest chain):
#       {template_id, template_version, template_sha256, rendered_prompt_sha256,
#        output}
#     where the two *_sha256 are `sha256:<64hex>` over the raw template bytes and
#     the rendered output bytes respectively.
#
# Exit codes:
#   0 — rendered successfully (provenance JSON on stdout)
#   1 — any usage / precondition / validation failure (message on stderr)
#
# **Last Updated:** 2026-09-24
# =============================================================================
set -euo pipefail

_fail() {
  echo "aid-render-prompt: $1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: aid-render-prompt.sh --template <file> --vars-json <json-file> --output <file>
EOF
}

# ---------------------------------------------------------------------------
# Dependency checks (external tools — fail closed if missing)
# ---------------------------------------------------------------------------
command -v jq  >/dev/null 2>&1 || _fail "jq not found in PATH"
command -v yq  >/dev/null 2>&1 || _fail "yq not found in PATH"
command -v sha256sum >/dev/null 2>&1 || _fail "sha256sum not found in PATH"

# ---------------------------------------------------------------------------
# Arg parsing (no eval)
# ---------------------------------------------------------------------------
TEMPLATE=""
VARS_JSON=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      [[ $# -ge 2 ]] || { usage; _fail "--template requires a value"; }
      TEMPLATE="$2"; shift 2 ;;
    --vars-json)
      [[ $# -ge 2 ]] || { usage; _fail "--vars-json requires a value"; }
      VARS_JSON="$2"; shift 2 ;;
    --output)
      [[ $# -ge 2 ]] || { usage; _fail "--output requires a value"; }
      OUTPUT="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage; _fail "unknown argument: $1" ;;
  esac
done

[[ -n "$TEMPLATE"  ]] || { usage; _fail "--template is required"; }
[[ -n "$VARS_JSON" ]] || { usage; _fail "--vars-json is required"; }
[[ -n "$OUTPUT"    ]] || { usage; _fail "--output is required"; }

[[ -f "$TEMPLATE"  && -r "$TEMPLATE"  ]] || _fail "template not found/readable: $TEMPLATE"
[[ -f "$VARS_JSON" && -r "$VARS_JSON" ]] || _fail "vars-json not found/readable: $VARS_JSON"

# ---------------------------------------------------------------------------
# Step 1: parse the frontmatter (declared variable set + template identity)
# ---------------------------------------------------------------------------
# A review round renders six prompts from one template, and each external
# process costs ~30 ms on the dev host, so the file is split in bash and every
# question below is ONE yq or jq pass (was ~30 processes per prompt, 2026-09-24).
#
# Frontmatter = everything strictly between the first `---` (line 1) and the
# next `---`; body = everything after that closing line.
_strip_nl() { local v="$1"; while [[ "$v" == *$'\n' ]]; do v="${v%$'\n'}"; done; printf -v "$2" '%s' "$v"; }
mapfile -t _L < "$TEMPLATE"
FRONTMATTER=""; BODY=""
if [[ "${_L[0]:-}" == "---" ]]; then
  _close=0
  for (( _i = 1; _i < ${#_L[@]}; _i++ )); do [[ "${_L[$_i]}" == "---" ]] && { _close=$_i; break; }; done
  if (( _close > 0 )); then
    (( _close > 1 )) && printf -v FRONTMATTER '%s\n' "${_L[@]:1:_close-1}"
    (( _close + 1 < ${#_L[@]} )) && printf -v BODY '%s\n' "${_L[@]:_close+1}"
  else
    printf -v FRONTMATTER '%s\n' "${_L[@]:1}"
  fi
fi
_strip_nl "$FRONTMATTER" FRONTMATTER; _strip_nl "$BODY" BODY
[[ -n "$FRONTMATTER" ]] || _fail "template has no YAML frontmatter (expected a leading '---' block): $TEMPLATE"

# Line 1: the verdict on `variables:`; 2: template_id; 3: template_version;
# then the declared variables, sorted and unique.
mapfile -t _FM < <(printf '%s\n' "$FRONTMATTER" | yq -o=json '.' 2>/dev/null | jq -r '
  (if (.variables // "") == "" then "missing"
   elif (.variables | type) != "array" then "type:\(.variables | type)"
   elif (.variables | length) == 0 then "empty"
   else "ok" end),
  (.template_id // "" | tostring), (.template_version // "" | tostring),
  (if (.variables | type) == "array" then .variables | map(tostring) | unique | .[] else empty end)' 2>/dev/null)
case "${_FM[0]:-}" in
  ok) ;;
  missing|"") _fail "template frontmatter has no 'variables:' list: $TEMPLATE" ;;
  type:*)     _fail "template frontmatter 'variables:' is not a list (got: ${_FM[0]#type:})" ;;
  empty)      _fail "template frontmatter 'variables:' list is empty" ;;
esac
TEMPLATE_ID="${_FM[1]}"; TEMPLATE_VERSION="${_FM[2]}"
DECLARED=("${_FM[@]:3}")

# ---------------------------------------------------------------------------
# Step 2: validate --vars-json (object, string values, no `{{` injection)
# ---------------------------------------------------------------------------
# Line 1: the verdict; then the key set, sorted and unique.
mapfile -t _VJ < <(jq -rs '
  if length != 1 then "json"
  elif (.[0] | type) != "object" then "object"
  else .[0]
    | ([to_entries[] | select((.value | type) != "string") | .key] | join(", ")) as $ns
    | ([to_entries[] | select((.value | type) == "string" and (.value | contains("{{"))) | .key] | join(", ")) as $inj
    | (if $ns != "" then "string:\($ns)" elif $inj != "" then "inject:\($inj)" else "ok" end),
      (keys | .[])
  end' "$VARS_JSON" 2>/dev/null)
case "${_VJ[0]:-}" in
  ok) ;;
  object)   _fail "vars-json is not a JSON object: $VARS_JSON" ;;
  string:*) _fail "vars-json values must all be strings; non-string key(s): ${_VJ[0]#string:}" ;;
  inject:*) _fail "vars-json values must not contain '{{'; offending key(s): ${_VJ[0]#inject:}" ;;
  *)        _fail "vars-json is not valid JSON: $VARS_JSON" ;;
esac
VARS_KEYS=("${_VJ[@]:1}")

# ---------------------------------------------------------------------------
# Step 3: declared set == vars key set (bidirectional, fail closed)
# ---------------------------------------------------------------------------
declare -A DECLARED_SET=() VARS_SET=()
for d in "${DECLARED[@]}"; do DECLARED_SET["$d"]=1; done
for k in "${VARS_KEYS[@]}"; do VARS_SET["$k"]=1; done
missing=""; unknown=""
for d in "${DECLARED[@]}"; do [[ -n "${VARS_SET[$d]:-}" ]] || missing+="${missing:+,}$d"; done
for k in "${VARS_KEYS[@]}"; do [[ -n "${DECLARED_SET[$k]:-}" ]] || unknown+="${unknown:+,}$k"; done
[[ -z "$missing" ]] || _fail "vars-json is MISSING declared variable(s): ${missing}"
[[ -z "$unknown" ]] || _fail "vars-json has UNKNOWN variable(s) not declared by the template: ${unknown}"

# ---------------------------------------------------------------------------
# Step 4: every body placeholder must be a declared variable
# ---------------------------------------------------------------------------
_rest="$BODY"
while [[ "$_rest" =~ \{\{([A-Za-z0-9_]+)\}\} ]]; do
  [[ -n "${DECLARED_SET[${BASH_REMATCH[1]}]:-}" ]] || _fail "template body uses undeclared placeholder: {{${BASH_REMATCH[1]}}}"
  _rest="${_rest#*"${BASH_REMATCH[0]}"}"
done

# ---------------------------------------------------------------------------
# Step 5: substitute (JSON-aware literal split/join — no eval/sed/string-glue)
# ---------------------------------------------------------------------------
rendered_tmp="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$rendered_tmp'" EXIT

# The body plus a single trailing newline — templates are authored to end
# with one. jq reduces over each {key,value}, replacing every literal
# "{{key}}" with the value. split(str)/join(str) are LITERAL (not regex), so no
# metacharacter can leak. `-j` emits raw bytes with no added trailing newline.
if ! jq -jn --arg body "${BODY}"$'\n' --slurpfile vars "$VARS_JSON" '
      ($vars[0] // {}) as $v
      | reduce ($v | to_entries[]) as $e ($body;
          split("{{" + $e.key + "}}") | join($e.value))
    ' > "$rendered_tmp" 2>/dev/null; then
  _fail "jq substitution pass failed"
fi

# ---------------------------------------------------------------------------
# Step 6: no residual placeholder may remain
# ---------------------------------------------------------------------------
_rendered="$(<"$rendered_tmp")"
if [[ "$_rendered" == *'{{'* ]]; then
  residual="$(grep -oE '\{\{[^}]*\}\}' "$rendered_tmp" | LC_ALL=C sort -u | paste -sd, - || true)"
  _fail "rendered output still contains placeholder(s): ${residual:-<malformed {{>}}"
fi

# ---------------------------------------------------------------------------
# Step 7: write --output and emit provenance JSON
# ---------------------------------------------------------------------------
out_dir="."; [[ "$OUTPUT" == */* ]] && out_dir="${OUTPUT%/*}"
[[ -d "${out_dir:-/}" ]] || _fail "output directory does not exist: $out_dir"
cp "$rendered_tmp" "$OUTPUT" || _fail "cannot write output: $OUTPUT"

{ read -r template_sha _; read -r rendered_sha _; } < <(sha256sum "$TEMPLATE" "$OUTPUT")

jq -n \
  --arg tid "$TEMPLATE_ID" \
  --arg tver "$TEMPLATE_VERSION" \
  --arg tsha "sha256:${template_sha}" \
  --arg rsha "sha256:${rendered_sha}" \
  --arg out "$OUTPUT" \
  '{template_id: $tid, template_version: $tver, template_sha256: $tsha, rendered_prompt_sha256: $rsha, output: $out}'
