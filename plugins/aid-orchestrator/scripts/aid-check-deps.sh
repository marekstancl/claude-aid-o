#!/usr/bin/env bash
# aid-check-deps.sh — Verify all AID system dependencies are installed and the
# correct variant. Fails fast with concrete install hints (P032 Step 9 deps
# documentation layer extension).
#
# Required at runtime: bash, git, jq, yq (mikefarah Go variant)
# Optional (development/dev-mode features): bats, direnv
# Optional (Telegram alerts): docker + docker compose, curl
#
# Exit codes: 0 = all required deps OK, 1 = at least one required dep missing.
# Optional dep absences print [WARN] but never fail the check.

set -uo pipefail

errors=0
warnings=0

green="$(tput setaf 2 2>/dev/null || true)"
red="$(tput setaf 1 2>/dev/null || true)"
yellow="$(tput setaf 3 2>/dev/null || true)"
reset="$(tput sgr0 2>/dev/null || true)"

# check_required <command> <install_hint> [variant_check_cmd]
check_required() {
  local cmd=$1 hint=$2 variant_check=${3:-}
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "${red}[FAIL]${reset} $cmd not installed. Install: $hint" >&2
    errors=$((errors + 1))
    return
  fi
  if [[ -n "$variant_check" ]]; then
    if ! eval "$variant_check" >/dev/null 2>&1; then
      echo "${red}[FAIL]${reset} $cmd installed but wrong variant. Required: $hint" >&2
      echo "       Detected: $($cmd --version 2>&1 | head -1)" >&2
      errors=$((errors + 1))
      return
    fi
  fi
  local v
  v=$("$cmd" --version 2>&1 | head -1)
  echo "${green}[OK]${reset}   $cmd: $v"
}

# check_optional <command> <install_hint> [purpose]
check_optional() {
  local cmd=$1 hint=$2 purpose=${3:-}
  if command -v "$cmd" >/dev/null 2>&1; then
    local v
    v=$("$cmd" --version 2>&1 | head -1)
    echo "${green}[OK]${reset}   $cmd: $v"
  else
    echo "${yellow}[WARN]${reset} $cmd not installed (${purpose:-optional}). Install: $hint" >&2
    warnings=$((warnings + 1))
  fi
}

echo "=== AID dependency check ==="
echo
echo "Required:"
check_required bash "OS default (bash >= 4.0)"
check_required git  "apt install git / brew install git"
check_required jq   "apt install jq / brew install jq"
check_required yq   "mikefarah Go variant — apt install yq (Debian/Ubuntu) or brew install yq (macOS) or download from https://github.com/mikefarah/yq/releases. NOT the Python kislyuk/yq PyPI package." \
                    "yq --version 2>&1 | grep -qi mikefarah"

echo
echo "Optional (development):"
check_optional bats   "apt install bats / brew install bats-core" "bats unit suite"
check_optional direnv "apt install direnv / brew install direnv"  "worktree .envrc auto-load"

echo
echo "Optional (Telegram alerts via svc-mcp-tg-bot):"
check_optional docker "https://docs.docker.com/engine/install/" "container deployment"
check_optional curl   "apt install curl / brew install curl"     "Telegram alerts via the shared send_alert()"

echo
if (( errors > 0 )); then
  echo "${red}FAIL: ${errors} required dependency(ies) missing.${reset}" >&2
  exit 1
fi
if (( warnings > 0 )); then
  echo "${yellow}OK with ${warnings} optional dep(s) missing — non-blocking.${reset}"
else
  echo "${green}All dependencies OK.${reset}"
fi
exit 0
