#!/usr/bin/env bash
# =============================================================================
# aid-ui-tool.sh — the one entry to the /aid-ui browser tools in lib/ui-fidelity.
# The installed plugin ships without node_modules: the first call runs `npm ci`
# there (lockfile pinned). Browser: $CHROME, else the newest Chromium in
# ~/.cache/ms-playwright, else Playwright's own.
#
#   glyph <url>... | glyph --sample <family> <text>    aid-ui-glyph-check.mjs
#   webp [--max-kb <n>] <src> <out.webp> <width> [quality 0-1]
#                                                      aid-ui-webp.mjs; the written file must be
#                                                      at most <n> kB (default 200), else exit 1
#   verify <args>                                      aid-ui-verify.mjs (arrives with the gate)
#
# Exit: the tool's own exit; 1 npm ci failed or file over --max-kb; 2 usage.
# =============================================================================
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/ui-fidelity" && pwd)"
usage() { echo "usage: aid-ui-tool.sh glyph|webp|verify <args>" >&2; exit 2; }
(( $# >= 1 )) || usage
tool="$1"; shift
case "$tool" in
  glyph)  js=aid-ui-glyph-check.mjs ;;
  webp)   js=aid-ui-webp.mjs ;;
  verify) js=aid-ui-verify.mjs ;;
  *) usage ;;
esac
[[ -f "$LIB/$js" ]] || { echo "ERROR: aid-ui-tool.sh: $LIB/$js missing" >&2; exit 1; }

max_kb=200
if [[ "$tool" == webp && "${1:-}" == --max-kb ]]; then
  [[ "${2:-}" =~ ^[0-9]+$ ]] || usage
  max_kb="$2"; shift 2
fi

if [[ ! -d "$LIB/node_modules" ]]; then
  echo "aid-ui-tool.sh: installing $LIB (npm ci)" >&2
  (cd "$LIB" && npm ci --no-audit --no-fund >&2) || { echo "ERROR: aid-ui-tool.sh: npm ci failed in $LIB" >&2; exit 1; }
fi

if [[ -z "${CHROME:-}" ]]; then
  CHROME="$(ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | sort -V | tail -1 || true)"
  export CHROME
fi

if [[ "$tool" != webp ]]; then exec node "$LIB/$js" "$@"; fi
node "$LIB/$js" "$@"
out="${2:?}"
size="$(stat -c %s "$out")"
if (( size > max_kb * 1024 )); then
  echo "ERROR: aid-ui-tool.sh: $out is $size bytes, over ${max_kb} kB; lower the width or quality" >&2
  exit 1
fi
