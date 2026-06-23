#!/usr/bin/env bash
# dg11-build-config.sh — build configuration consistency check
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — optional build config validator command
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. argv provided → run it; map exit code; skip native logic
#   2. Look for build config files: vite.config.*, webpack.config.*, rollup.config.*, tsconfig.json
#   3. None found → unverifiable
#   4. tsconfig.json: check paths aliases point to existing dirs; check include has ≥1 match
#   5. vite.config.*: grep manualChunks; check each local reference exists
#   6. webpack.config.*: check entry file references exist
#   7. rollup.config.*: check input file references exist
#   8. Exit 0 if clean, exit 1 if issues, exit 2 if cannot analyze

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# Step 1: argv provided → delegate to external command
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  echo "dg11: running override command: $*"
  cmd_output=""
  cmd_exit=0

  if cmd_output="$(cd "$ROOT" && "$@" 2>&1)"; then
    echo "dg11: command passed"
    echo "$cmd_output"
    exit 0
  else
    cmd_exit=$?
    echo "dg11: command failed (exit ${cmd_exit})"
    echo "$cmd_output"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Discover build config files
# ---------------------------------------------------------------------------
shopt -s nullglob

VITE_CONFIGS=("${ROOT}"/vite.config.{js,ts,mjs,cjs,mts})
WEBPACK_CONFIGS=("${ROOT}"/webpack.config.{js,ts,mjs,cjs})
ROLLUP_CONFIGS=("${ROOT}"/rollup.config.{js,ts,mjs,cjs})
TSCONFIG="${ROOT}/tsconfig.json"

shopt -u nullglob

FOUND_ANY=false
for cfg in "${VITE_CONFIGS[@]}" "${WEBPACK_CONFIGS[@]}" "${ROLLUP_CONFIGS[@]}"; do
  [[ -f "$cfg" ]] && FOUND_ANY=true && break
done
[[ -f "$TSCONFIG" ]] && FOUND_ANY=true

if [[ "$FOUND_ANY" == "false" ]]; then
  echo "dg11: unverifiable — no build config files found in ${ROOT}"
  echo "dg11: searched for vite.config.*, webpack.config.*, rollup.config.*, tsconfig.json"
  exit 2
fi

FAIL=0
FAIL_DETAILS=()

# ---------------------------------------------------------------------------
# Step 3: tsconfig.json — check paths aliases and include patterns
# ---------------------------------------------------------------------------
if [[ -f "$TSCONFIG" ]]; then
  echo "dg11: checking tsconfig.json"

  if command -v jq >/dev/null 2>&1; then
    # Check compilerOptions.paths: each alias should point to an existing dir/file
    while IFS= read -r alias_path; do
      [[ -z "$alias_path" ]] && continue
      # Strip trailing /* glob for directory check
      check_path="${alias_path%/\*}"
      check_path="${check_path%\*}"
      # Resolve relative to tsconfig location (ROOT)
      resolved="${ROOT}/${check_path}"
      if [[ ! -e "$resolved" ]]; then
        FAIL=1
        FAIL_DETAILS+=("tsconfig.json: paths alias '${alias_path}' → '${check_path}' does not exist")
        echo "dg11: FAIL — tsconfig paths alias '${alias_path}' → '${check_path}' does not exist"
      fi
    done < <(jq -r '(.compilerOptions.paths // {}) | to_entries[].value[] // empty' "$TSCONFIG" 2>/dev/null || true)

    # Check include patterns have at least one matching file
    include_count=0
    include_count="$(jq -r '(.include // []) | length' "$TSCONFIG" 2>/dev/null || echo "0")"
    if [[ "$include_count" =~ ^[0-9]+$ && "$include_count" -gt 0 ]]; then
      # Read include patterns and check at least one file matches each
      while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        # Expand pattern relative to ROOT using find (simple glob expansion)
        match_count=0
        match_count="$(find "$ROOT" -path "${ROOT}/${pattern}" 2>/dev/null | head -1 | wc -l)" || true
        if [[ "$match_count" -eq 0 ]]; then
          # Also try with shell glob
          shopt -s nullglob globstar
          matches=("${ROOT}"/${pattern})
          shopt -u nullglob globstar
          if [[ ${#matches[@]} -eq 0 ]]; then
            FAIL=1
            FAIL_DETAILS+=("tsconfig.json: include pattern '${pattern}' matches 0 files")
            echo "dg11: FAIL — tsconfig include pattern '${pattern}' matches 0 files"
          fi
        fi
      done < <(jq -r '(.include // [])[]' "$TSCONFIG" 2>/dev/null || true)
    fi
  else
    echo "dg11: note — jq not available; skipping tsconfig.json deep analysis"
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: vite.config.* — check manualChunks local file references
# ---------------------------------------------------------------------------
for vcfg in "${VITE_CONFIGS[@]}"; do
  [[ -f "$vcfg" ]] || continue
  rel_vcfg="${vcfg#"$ROOT/"}"
  echo "dg11: checking ${rel_vcfg}"

  # Extract local path references from manualChunks values using grep/sed
  # Matches strings like: ['./src/lib/foo'], ["../lib/bar"], ['src/utils']
  # We only care about paths starting with ./ or ../ (relative local paths)
  while IFS= read -r raw_path; do
    [[ -z "$raw_path" ]] && continue
    # Strip quotes and trailing content
    clean_path="$(printf '%s' "$raw_path" | sed "s/['\"]//g" | sed 's/[,\]].*//')"
    [[ -z "$clean_path" ]] && continue
    # Only check relative paths
    if [[ "$clean_path" == ./* || "$clean_path" == ../* ]]; then
      resolved_path="${ROOT}/${clean_path}"
      # Normalize path (remove ../)
      if ! [[ -e "$resolved_path" || -e "${resolved_path}.js" || -e "${resolved_path}.ts" || -e "${resolved_path}.mjs" ]]; then
        FAIL=1
        FAIL_DETAILS+=("${rel_vcfg}: manualChunks references '${clean_path}' which does not exist")
        echo "dg11: FAIL — ${rel_vcfg}: manualChunks '${clean_path}' does not exist"
      fi
    fi
  done < <(
    # Extract array values from manualChunks blocks
    grep -oE "'\./[^']+'" "$vcfg" 2>/dev/null || true
    grep -oE '"\./[^"]+' "$vcfg" 2>/dev/null | sed 's/^"//' || true
    grep -oE "'\.\./[^']+" "$vcfg" 2>/dev/null | sed "s/^'//" || true
  )
done

# ---------------------------------------------------------------------------
# Step 5: webpack.config.* — check entry file existence
# ---------------------------------------------------------------------------
for wcfg in "${WEBPACK_CONFIGS[@]}"; do
  [[ -f "$wcfg" ]] || continue
  rel_wcfg="${wcfg#"$ROOT/"}"
  echo "dg11: checking ${rel_wcfg}"

  # Extract entry: './src/index.js' style references
  while IFS= read -r entry_path; do
    [[ -z "$entry_path" ]] && continue
    if [[ "$entry_path" == ./* || "$entry_path" == ../* ]]; then
      resolved="${ROOT}/${entry_path}"
      if ! [[ -e "$resolved" ]]; then
        FAIL=1
        FAIL_DETAILS+=("${rel_wcfg}: entry '${entry_path}' does not exist")
        echo "dg11: FAIL — ${rel_wcfg}: entry '${entry_path}' does not exist"
      fi
    fi
  done < <(
    grep -oE "entry\s*:\s*['\"][^'\"]+['\"]" "$wcfg" 2>/dev/null \
      | grep -oE "['\"][^'\"]+['\"]" \
      | tr -d "'\"" || true
  )
done

# ---------------------------------------------------------------------------
# Step 6: rollup.config.* — check input file existence
# ---------------------------------------------------------------------------
for rcfg in "${ROLLUP_CONFIGS[@]}"; do
  [[ -f "$rcfg" ]] || continue
  rel_rcfg="${rcfg#"$ROOT/"}"
  echo "dg11: checking ${rel_rcfg}"

  while IFS= read -r input_path; do
    [[ -z "$input_path" ]] && continue
    if [[ "$input_path" == ./* || "$input_path" == ../* ]]; then
      resolved="${ROOT}/${input_path}"
      if ! [[ -e "$resolved" ]]; then
        FAIL=1
        FAIL_DETAILS+=("${rel_rcfg}: input '${input_path}' does not exist")
        echo "dg11: FAIL — ${rel_rcfg}: input '${input_path}' does not exist"
      fi
    fi
  done < <(
    grep -oE "input\s*:\s*['\"][^'\"]+['\"]" "$rcfg" 2>/dev/null \
      | grep -oE "['\"][^'\"]+['\"]" \
      | tr -d "'\"" || true
  )
done

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "$FAIL" -eq 0 ]]; then
  echo "dg11: pass — build configuration consistent (no missing references detected)"
  exit 0
else
  echo "dg11: fail — build configuration issues detected:"
  for detail in "${FAIL_DETAILS[@]}"; do
    echo "  - ${detail}"
  done
  exit 1
fi
