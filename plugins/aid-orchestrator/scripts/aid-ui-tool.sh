#!/usr/bin/env bash
# =============================================================================
# aid-ui-tool.sh — the one entry to the /aid-ui browser tools in lib/ui-fidelity.
# The installed plugin ships without node_modules: a call runs `npm ci` there
# (lockfile pinned) unless node_modules/.aid-installed holds the sha256 of the
# current package-lock.json. The marker is written only after `npm ci` exits 0;
# a failed install removes node_modules. Installs run under flock on
# lib/ui-fidelity/.aid-install.lock, so two first calls never race. Browser: $CHROME, else the newest Chromium in
# ~/.cache/ms-playwright, else Playwright's own.
#
#   glyph <url>... | glyph --sample <family> <text>    aid-ui-glyph-check.mjs
#   webp [--max-kb <n>] <src> <out.webp> <width> [quality 0-1]
#                                                      aid-ui-webp.mjs; the written file must be
#                                                      at most <n> kB (default 200), else exit 1
#   verify <args>                                      aid-ui-verify.mjs (arrives with the gate)
#   png <src.svg> <out.png> <width>                    aid-ui-png.mjs: an SVG as a PNG (transparent)
#   measure [--storage-state <f>] [--build <id>] <base url> <out.json> <page>...   aid-ui-measure.mjs: what the built site uses
#                                                      (control roles, fields, type, breakpoints) for
#                                                      the project design standard (step 7 bod 4)
#   logo-sheet --spec <sheet.json> [--root <project>]  aid-ui-logo-sheet.mjs: every logo direction where
#   logo-sheet --contact <dir> --out <png> [--root]     ... or the curation contact sheet of every concept PNG in <dir>
#                                                      it will live (header, tab 16 px, phone icon, avatar,
#                                                      business card) as logo-<id>.png, and logo-prehled.png
#                                                      of all directions next to the competitors' logos
#                                                      (step 1i Rozcestník; spec format in the module header)
#   vectorize <in.png> <out.svg> [--speckle N] [--corner N] [--length F] [--size N]
#                                                      scripts/aid-ui-vectorize.py: a generated raster
#                                                      concept (aid-ui-logo-gen.py) as one black SVG symbol,
#                                                      viewBox 0 0 256 256. vtracer + Pillow (MIT/HPND) live
#                                                      in ${AID_UI_PYVEC:-~/.cache/aid-ui/pyvec}, a venv made
#                                                      on first use like pyfont below
#   wordmark --spec <wordmark.json>                    scripts/aid-ui-wordmark.py: the logo with the
#                                                      name (master with live text, outlines, logo/
#                                                      variants). Python fontTools + brotli (MIT) live in
#                                                      ${AID_UI_PYFONT:-~/.cache/aid-ui/pyfont}, a venv made
#                                                      on first use (pinned versions, under flock); nothing
#                                                      is installed into the system or the project.
#
# Exit: the tool's own exit; 1 npm ci failed or file over --max-kb; 2 usage.
# =============================================================================
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/ui-fidelity" && pwd)"
usage() { echo "usage: aid-ui-tool.sh glyph|webp|verify|png|measure|motion|logo-sheet|vectorize|wordmark <args>" >&2; exit 2; }
(( $# >= 1 )) || usage
tool="$1"; shift
if [[ "$tool" == wordmark ]]; then
  VENV="${AID_UI_PYFONT:-$HOME/.cache/aid-ui/pyfont}"
  PINS="fonttools==4.60.1 brotli==1.1.0"
  mkdir -p "$(dirname "$VENV")"
  exec 8>"$VENV.lock"; flock 8
  if [[ "$(cat "$VENV/.aid-installed" 2>/dev/null)" != "$PINS" ]]; then
    echo "aid-ui-tool.sh: installing $PINS into $VENV" >&2
    rm -rf "$VENV"
    if ! { python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet $PINS >&2; }; then
      rm -rf "$VENV"; echo "ERROR: aid-ui-tool.sh: could not install $PINS into $VENV" >&2; exit 1
    fi
    printf '%s' "$PINS" > "$VENV/.aid-installed"
  fi
  flock -u 8; exec 8>&-
  exec "$VENV/bin/python" "$(dirname "${BASH_SOURCE[0]}")/aid-ui-wordmark.py" "$@"
fi
if [[ "$tool" == vectorize ]]; then
  VENV="${AID_UI_PYVEC:-$HOME/.cache/aid-ui/pyvec}"
  PINS="vtracer==0.6.15 pillow==12.3.0"
  mkdir -p "$(dirname "$VENV")"
  exec 8>"$VENV.lock"; flock 8
  if [[ "$(cat "$VENV/.aid-installed" 2>/dev/null)" != "$PINS" ]]; then
    echo "aid-ui-tool.sh: installing $PINS into $VENV" >&2
    rm -rf "$VENV"
    if ! { python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet $PINS >&2; }; then
      rm -rf "$VENV"; echo "ERROR: aid-ui-tool.sh: could not install $PINS into $VENV" >&2; exit 1
    fi
    printf '%s' "$PINS" > "$VENV/.aid-installed"
  fi
  flock -u 8; exec 8>&-
  exec "$VENV/bin/python" "$(dirname "${BASH_SOURCE[0]}")/aid-ui-vectorize.py" "$@"
fi
case "$tool" in
  glyph)  js=aid-ui-glyph-check.mjs ;;
  webp)   js=aid-ui-webp.mjs ;;
  verify) js=aid-ui-verify.mjs ;;
  png)    js=aid-ui-png.mjs ;;
  logo-sheet) js=aid-ui-logo-sheet.mjs ;;
  measure) js=aid-ui-measure.mjs ;;
  motion) js=aid-ui-motion.mjs ;;
  *) usage ;;
esac
[[ -f "$LIB/$js" ]] || { echo "ERROR: aid-ui-tool.sh: $LIB/$js missing" >&2; exit 1; }

max_kb=200
if [[ "$tool" == webp && "${1:-}" == --max-kb ]]; then
  [[ "${2:-}" =~ ^[0-9]+$ ]] || usage
  max_kb="$2"; shift 2
fi

# ensure_installed — npm ci unless the marker matches the lockfile (caller holds the lock)
ensure_installed() {
  local want marker="$LIB/node_modules/.aid-installed"
  want="$(sha256sum "$LIB/package-lock.json" | cut -d' ' -f1)"
  [[ -f "$marker" && "$(cat "$marker")" == "$want" ]] && return 0
  echo "aid-ui-tool.sh: installing $LIB (npm ci)" >&2
  if ! (cd "$LIB" && npm ci --no-audit --no-fund >&2); then
    rm -rf "$LIB/node_modules"
    echo "ERROR: aid-ui-tool.sh: npm ci failed in $LIB" >&2
    return 1
  fi
  printf '%s\n' "$want" > "$marker"
}
exec 9>"$LIB/.aid-install.lock"
flock 9
ensure_installed || exit 1
flock -u 9; exec 9>&-

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
