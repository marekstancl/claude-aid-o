#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared bash library for AID pipeline scripts
#
# Sourced by: aid-plan-to-epic.sh, aid-epic-to-json.sh, aid-json-to-run.sh,
#             aid-queue-add.sh, aid-auto-pipeline.sh
#
# Provides: parse_frontmatter, extract_section, extract_subsection,
#           slugify, check_prerequisites, error_exit, iso_timestamp
#
# Requirements: bash 4.0+, jq
# Portability:  macOS (BSD) + Linux (GNU)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Guard: prevent direct execution — this file must be sourced, not run.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: common.sh must be sourced, not executed directly." >&2
  echo "Usage: source \"\$(dirname \"\$0\")/lib/common.sh\"" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# error_exit(msg, code)
#
# Print a JSON-formatted error to stderr and exit with the given code.
#   msg  — human-readable error message (required)
#   code — numeric exit code (required; 1=validation, 2=dependency, 3=I/O)
#
# Output (stderr): {"error": "<msg>", "code": <code>}
# ---------------------------------------------------------------------------
error_exit() {
  local msg="${1:?error_exit requires a message}"
  local code="${2:?error_exit requires an exit code}"

  # Escape double quotes and backslashes in the message for valid JSON
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"

  printf '{"error": "%s", "code": %d}\n' "$msg" "$code" >&2
  exit "$code"
}

# ---------------------------------------------------------------------------
# iso_timestamp()
#
# Return the current UTC time in ISO 8601 format.
# Uses only POSIX-portable date flags.
#
# Output (stdout): e.g. 2026-02-28T14:30:00Z
# ---------------------------------------------------------------------------
iso_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ---------------------------------------------------------------------------
# check_prerequisites()
#
# Verify runtime prerequisites before any pipeline script proceeds:
#   1. bash version >= 4.0
#   2. jq is available on PATH
#
# Exits with code 2 if any check fails, printing install guidance.
# ---------------------------------------------------------------------------
check_prerequisites() {
  local failed=0

  # Check bash version (major must be >= 4)
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: bash 4.0+ is required (found ${BASH_VERSION})." >&2
    echo "  macOS:  brew install bash" >&2
    echo "  Linux:  bash is typically 4.0+ — update via your package manager" >&2
    failed=1
  fi

  # Check jq availability
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found on PATH." >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Linux:  sudo apt install jq  (Debian/Ubuntu)" >&2
    echo "          sudo dnf install jq  (Fedora/RHEL)" >&2
    failed=1
  fi

  if [[ "$failed" -eq 1 ]]; then
    error_exit "Missing prerequisites — see messages above" 2
  fi
}

# ---------------------------------------------------------------------------
# slugify(text)
#
# Convert arbitrary text into a URL/filename-safe slug.
#   - Lowercase all characters
#   - Replace any non-alphanumeric character with a hyphen
#   - Collapse consecutive hyphens into one
#   - Strip leading/trailing hyphens
#   - Truncate to 40 characters
#
# Args:
#   text — the string to slugify (passed as $1 or via stdin)
#
# Output (stdout): the slugified string, e.g. "my-feature-title"
# ---------------------------------------------------------------------------
slugify() {
  local text="${1:-}"

  # If no argument, read from stdin (supports piping)
  if [[ -z "$text" ]]; then
    read -r text
  fi

  echo "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40
}

# ---------------------------------------------------------------------------
# parse_frontmatter(file)
#
# Extract YAML frontmatter from a markdown file. Frontmatter is the content
# between the FIRST two lines that are exactly "---" (with optional trailing
# whitespace / carriage return).
#
# Handles:
#   - Windows CRLF line endings (strips \r)
#   - Only reads between FIRST two --- lines (ignores --- in code blocks)
#   - Multi-line values by joining continuation lines (lines starting with
#     whitespace are appended to the previous key's value with a space)
#
# Args:
#   file — path to the markdown file
#
# Output (stdout): key=value pairs, one per line
#   Example:
#     id=E-001
#     status=active
#     plan_ref=2026-02-15-plan.md
# ---------------------------------------------------------------------------
parse_frontmatter() {
  local file="${1:?parse_frontmatter requires a file path}"

  if [[ ! -f "$file" ]]; then
    error_exit "File not found: $file" 3
  fi

  # Use awk to extract content between the first two --- delimiters,
  # strip carriage returns, then process key=value pairs.
  awk '
    BEGIN { in_fm = 0; fence_count = 0 }
    {
      # Strip carriage return for Windows CRLF compatibility
      gsub(/\r$/, "")

      # Match lines that are exactly "---" (with optional trailing whitespace)
      if ($0 ~ /^---[[:space:]]*$/) {
        fence_count++
        if (fence_count == 1) { in_fm = 1; next }
        if (fence_count == 2) { exit }
      }

      if (in_fm) print
    }
  ' "$file" | awk '
    # Process YAML key: value lines into key=value output.
    # Continuation lines (starting with whitespace) are joined to the
    # previous key value.
    #
    # NOTE: Uses only POSIX awk — no gawk-specific match(s,r,a) 3-arg form.
    BEGIN { key = ""; val = "" }
    {
      # Skip comment lines
      if ($0 ~ /^[[:space:]]*#/) next

      # Skip blank lines
      if ($0 ~ /^[[:space:]]*$/) next

      # Continuation line (starts with whitespace, and we have a prior key)
      if ($0 ~ /^[[:space:]]/ && key != "") {
        # Trim leading whitespace from continuation
        sub(/^[[:space:]]+/, "", $0)
        val = val " " $0
        next
      }

      # Flush previous key=value if we have one
      if (key != "") {
        print key "=" val
      }

      # Parse new key: value using POSIX-compatible field splitting.
      # Match lines of the form: key: value  (key starts with letter/underscore)
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*:/) {
        # Extract key: everything before the first colon
        colon_pos = index($0, ":")
        key = substr($0, 1, colon_pos - 1)
        val = substr($0, colon_pos + 1)
        # Trim whitespace from key and value
        sub(/[[:space:]]+$/, "", key)
        sub(/^[[:space:]]+/, "", val)
        sub(/[[:space:]]+$/, "", val)
      } else {
        # Line does not match key: value — skip
        key = ""
        val = ""
        next
      }
    }
    END {
      if (key != "") print key "=" val
    }
  '
}

# ---------------------------------------------------------------------------
# extract_section(file, header)
#
# Extract the body content of an H2 section (## Header) from a markdown file.
# Returns all lines between the matching ## header and the next ## header
# (or end of file), excluding the header line itself.
#
# Args:
#   file   — path to the markdown file
#   header — the H2 header text to find (without the ## prefix)
#
# Output (stdout): section body (may be empty string for empty sections)
# ---------------------------------------------------------------------------
extract_section() {
  local file="${1:?extract_section requires a file path}"
  local header="${2:?extract_section requires a header name}"

  if [[ ! -f "$file" ]]; then
    error_exit "File not found: $file" 3
  fi

  awk -v header="$header" '
    BEGIN { found = 0 }
    {
      # Strip carriage return
      gsub(/\r$/, "")

      # Check for the target H2 header
      if ($0 ~ /^##[[:space:]]/ && !($0 ~ /^###/)) {
        # Extract the header text (strip "## " prefix and trim)
        line = $0
        sub(/^##[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)

        if (found) {
          # We hit the next H2 — stop
          exit
        }

        if (line == header) {
          found = 1
          next
        }
      } else if (found) {
        print
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# extract_subsection(file, h2, h3)
#
# Extract content of an H3 subsection (### Header) that lives within
# a specific H2 section (## Header).
#
# Returns all lines between the matching ### header and the next ### or ##
# header (or end of the H2 section), excluding the ### header line itself.
#
# Args:
#   file — path to the markdown file
#   h2   — the H2 section name (without ## prefix)
#   h3   — the H3 subsection name (without ### prefix)
#
# Output (stdout): subsection body
# ---------------------------------------------------------------------------
extract_subsection() {
  local file="${1:?extract_subsection requires a file path}"
  local h2="${2:?extract_subsection requires an H2 header name}"
  local h3="${3:?extract_subsection requires an H3 header name}"

  if [[ ! -f "$file" ]]; then
    error_exit "File not found: $file" 3
  fi

  awk -v h2="$h2" -v h3="$h3" '
    BEGIN { in_h2 = 0; in_h3 = 0 }
    {
      # Strip carriage return
      gsub(/\r$/, "")

      # Detect H2 boundary
      if ($0 ~ /^##[[:space:]]/ && !($0 ~ /^###/)) {
        line = $0
        sub(/^##[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)

        if (in_h2 && !in_h3) {
          # Leaving our H2 without finding H3 — nothing to return
          exit
        }
        if (in_h3) {
          # Leaving the H2 that contained our H3 — stop
          exit
        }

        if (line == h2) {
          in_h2 = 1
        } else {
          in_h2 = 0
        }
        next
      }

      # Only look for H3 inside the target H2
      if (in_h2 && $0 ~ /^###[[:space:]]/) {
        line = $0
        sub(/^###[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)

        if (in_h3) {
          # Hit the next H3 — stop
          exit
        }

        if (line == h3) {
          in_h3 = 1
          next
        }
      }

      if (in_h3) {
        print
      }
    }
  ' "$file"
}
