#!/usr/bin/env bash
# aid-ui-design-to-css.sh — DESIGN.md frontmatter tokens -> CSS custom properties.
#
# Usage: aid-ui-design-to-css.sh <DESIGN.md> <out.css>
#   colors.<n>            -> --color-<n>
#   typography.<role>.fontFamily|fontSize|fontWeight|lineHeight|letterSpacing
#                         -> --font-<role>-{family,size,weight,line-height,letter-spacing}
#   rounded.<n>           -> --radius-<n>
#   spacing.<n>           -> --space-<n>
# Everything else (components, unknown keys) is ignored.
#
# Exit: 0 written; 1 no/invalid frontmatter or no tokens (<out.css> untouched); 2 usage.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $(basename "$0") <DESIGN.md> <out.css>" >&2
  exit 2
fi
design="$1"; out="$2"

fail() { echo "ERROR: $design: $1" >&2; exit 1; }

[ -r "$design" ] || fail "file not readable"

# Frontmatter = lines between a first-line '---' and the next '---'.
fm=$(awk 'NR==1 { if ($0 != "---") exit 3; next } $0 == "---" { closed=1; exit } { print } END { if (!closed) exit 3 }' "$design") \
  || fail "no YAML frontmatter"

json=$(printf '%s\n' "$fm" | yq -o=json '.' 2>/dev/null) || fail "invalid YAML frontmatter"

css=$(printf '%s\n' "$json" | jq -r '
  def group($g; $p): (.[$g] // {}) | to_entries[] | "  --\($p)-\(.key): \(.value);";
  group("colors"; "color"),
  ((.typography // {}) | to_entries[] | .key as $role | .value | to_entries[]
    | select(.key | IN("fontFamily", "fontSize", "fontWeight", "lineHeight", "letterSpacing"))
    | "  --font-\($role)-\(.key | sub("^font"; "") | gsub("(?<c>[A-Z])"; "-\(.c)") | ltrimstr("-") | ascii_downcase): \(.value);"),
  group("rounded"; "radius"),
  group("spacing"; "space")
' 2>/dev/null) || fail "token groups are not key/value maps"

[ -n "$css" ] || fail "no tokens (colors, typography, rounded, spacing)"

tmp=$(mktemp "$out.XXXXXX") || fail "cannot write next to $out"
trap 'rm -f "$tmp"' EXIT
printf ':root {\n%s\n}\n' "$css" > "$tmp"
mv "$tmp" "$out"
