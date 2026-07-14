#!/usr/bin/env bash
# =============================================================================
# aid-render-prompt.sh — deterministic, JSON-aware prompt-template renderer
# (P065, E-065-1_7, Step 4)
#
# Renders a versioned prompt template (e.g. defaults/prompts/c3-audit-prompt-v1.md)
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
# **Last Updated:** 2026-07-14
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
# Extract the YAML frontmatter block: everything strictly between the first
# `---` (which must be line 1) and the next `---`.
FRONTMATTER="$(awk 'NR==1 && $0=="---"{infm=1; next} infm && $0=="---"{exit} infm{print}' "$TEMPLATE")"
[[ -n "$FRONTMATTER" ]] || _fail "template has no YAML frontmatter (expected a leading '---' block): $TEMPLATE"

# Declared variables (fail closed if `variables:` is absent or not a sequence).
declared_raw="$(printf '%s\n' "$FRONTMATTER" | yq -r '.variables // "__MISSING__"' 2>/dev/null || true)"
[[ "$declared_raw" != "__MISSING__" && -n "$declared_raw" ]] \
  || _fail "template frontmatter has no 'variables:' list: $TEMPLATE"

declared_type="$(printf '%s\n' "$FRONTMATTER" | yq -r '.variables | type' 2>/dev/null || echo "")"
[[ "$declared_type" == "!!seq" ]] || _fail "template frontmatter 'variables:' is not a list (got: ${declared_type:-none})"

mapfile -t DECLARED < <(printf '%s\n' "$FRONTMATTER" | yq -r '.variables[]' 2>/dev/null | LC_ALL=C sort -u)
[[ ${#DECLARED[@]} -gt 0 ]] || _fail "template frontmatter 'variables:' list is empty"

TEMPLATE_ID="$(printf '%s\n' "$FRONTMATTER" | yq -r '.template_id // ""' 2>/dev/null || echo "")"
TEMPLATE_VERSION="$(printf '%s\n' "$FRONTMATTER" | yq -r '.template_version // ""' 2>/dev/null || echo "")"

# ---------------------------------------------------------------------------
# Step 2: validate --vars-json (object, string values, no `{{` injection)
# ---------------------------------------------------------------------------
jq -e . "$VARS_JSON" >/dev/null 2>&1 || _fail "vars-json is not valid JSON: $VARS_JSON"
[[ "$(jq -r 'type' "$VARS_JSON")" == "object" ]] || _fail "vars-json is not a JSON object: $VARS_JSON"

# All values must be strings.
non_string="$(jq -r '[to_entries[] | select((.value | type) != "string") | .key] | join(", ")' "$VARS_JSON")"
[[ -z "$non_string" ]] || _fail "vars-json values must all be strings; non-string key(s): ${non_string}"

# No value may contain the placeholder opener `{{` (prevents value→placeholder bleed).
inject_keys="$(jq -r '[to_entries[] | select(.value | contains("{{")) | .key] | join(", ")' "$VARS_JSON")"
[[ -z "$inject_keys" ]] || _fail "vars-json values must not contain '{{'; offending key(s): ${inject_keys}"

# vars-json key set (sorted, deduped).
mapfile -t VARS_KEYS < <(jq -r 'keys_unsorted[]' "$VARS_JSON" | LC_ALL=C sort -u)

# ---------------------------------------------------------------------------
# Step 3: declared set == vars key set (bidirectional, fail closed)
# ---------------------------------------------------------------------------
declared_joined="$(printf '%s\n' "${DECLARED[@]}")"
vars_joined="$(printf '%s\n' "${VARS_KEYS[@]}")"

missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$declared_joined") <(printf '%s\n' "$vars_joined") | paste -sd, - || true)"
unknown="$(LC_ALL=C comm -13 <(printf '%s\n' "$declared_joined") <(printf '%s\n' "$vars_joined") | paste -sd, - || true)"
[[ -z "$missing" ]] || _fail "vars-json is MISSING declared variable(s): ${missing}"
[[ -z "$unknown" ]] || _fail "vars-json has UNKNOWN variable(s) not declared by the template: ${unknown}"

# ---------------------------------------------------------------------------
# Step 4: every body placeholder must be a declared variable
# ---------------------------------------------------------------------------
# Body = template with the frontmatter block removed (so `variables:` in the
# frontmatter is never mistaken for a body placeholder — it has no `{{}}` anyway,
# but the body is what we substitute into).
BODY="$(awk 'BEGIN{fm=0; done=0}
  NR==1 && $0=="---" {fm=1; next}
  fm==1 && done==0 && $0=="---" {done=1; next}
  fm==1 && done==0 {next}
  {print}' "$TEMPLATE")"

# Collect declared set into an associative array for O(1) membership tests.
declare -A DECLARED_SET=()
for d in "${DECLARED[@]}"; do DECLARED_SET["$d"]=1; done

# Well-formed placeholders in the body.
mapfile -t BODY_PLACEHOLDERS < <(printf '%s\n' "$BODY" | grep -oE '\{\{[A-Za-z0-9_]+\}\}' | LC_ALL=C sort -u || true)
for ph in "${BODY_PLACEHOLDERS[@]}"; do
  name="${ph#\{\{}"; name="${name%\}\}}"
  [[ -n "${DECLARED_SET[$name]:-}" ]] || _fail "template body uses undeclared placeholder: {{${name}}}"
done

# ---------------------------------------------------------------------------
# Step 5: substitute (JSON-aware literal split/join — no eval/sed/string-glue)
# ---------------------------------------------------------------------------
body_tmp="$(mktemp)"
rendered_tmp="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$body_tmp' '$rendered_tmp'" EXIT

# Write the EXACT body bytes (awk above drops the trailing newline of its input
# stream; re-add a single trailing newline to match the template's own final
# newline — templates are authored to end with one).
printf '%s\n' "$BODY" > "$body_tmp"

# jq reduces over each {key,value}, replacing every literal "{{key}}" with the
# value. split(str)/join(str) are LITERAL (not regex), so no metacharacter can
# leak. `-j` emits raw bytes with no added trailing newline.
if ! jq -jn --rawfile body "$body_tmp" --slurpfile vars "$VARS_JSON" '
      ($vars[0] // {}) as $v
      | reduce ($v | to_entries[]) as $e ($body;
          split("{{" + $e.key + "}}") | join($e.value))
    ' > "$rendered_tmp" 2>/dev/null; then
  _fail "jq substitution pass failed"
fi

# ---------------------------------------------------------------------------
# Step 6: no residual placeholder may remain
# ---------------------------------------------------------------------------
if grep -qE '\{\{' "$rendered_tmp"; then
  residual="$(grep -oE '\{\{[^}]*\}\}' "$rendered_tmp" | LC_ALL=C sort -u | paste -sd, - || true)"
  _fail "rendered output still contains placeholder(s): ${residual:-<malformed {{>}}"
fi

# ---------------------------------------------------------------------------
# Step 7: write --output and emit provenance JSON
# ---------------------------------------------------------------------------
out_dir="$(dirname "$OUTPUT")"
[[ -d "$out_dir" ]] || _fail "output directory does not exist: $out_dir"
cp "$rendered_tmp" "$OUTPUT" || _fail "cannot write output: $OUTPUT"

template_sha="sha256:$(sha256sum "$TEMPLATE" | awk '{print $1}')"
rendered_sha="sha256:$(sha256sum "$OUTPUT"   | awk '{print $1}')"

jq -n \
  --arg tid "$TEMPLATE_ID" \
  --arg tver "$TEMPLATE_VERSION" \
  --arg tsha "$template_sha" \
  --arg rsha "$rendered_sha" \
  --arg out "$OUTPUT" \
  '{template_id: $tid, template_version: $tver, template_sha256: $tsha, rendered_prompt_sha256: $rsha, output: $out}'
