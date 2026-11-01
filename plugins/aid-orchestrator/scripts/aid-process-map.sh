#!/usr/bin/env bash
# =============================================================================
# aid-process-map.sh — process maps (AID 3.15.0, P118). Standard: /ecosystem/specs/procesni-mapy
#
#   aid-process-map.sh check <docs/procesy/<name>.mapa.yaml>
#   aid-process-map.sh build <mapa.yaml> [--no-render] [--out <dir>]
#
# The work is in aid-process-map.py next to this file (resolved from this script's own path, so it runs
# from any project root, with or without $AID_PLUGIN_PATH). Exit: 0 ok, 1 findings, 2 usage/unreadable.
# =============================================================================
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/aid-process-map.py" "$@"
