#!/usr/bin/env bash
# =============================================================================
# aid-queue-add.sh — Add an EPIC entry to epic-queue.yaml
#
# Usage:
#   ./aid-queue-add.sh \
#     --epic-id <E-xxx> --epic-path <path> --queue-yaml <path> \
#     [--priority <medium>] [--depends-on <E-xxx,E-yyy>] [--plan-ref <path>]
#
# Validates against duplicates, checks dependency references, and runs
# Kahn's algorithm for cycle detection on the full dependency graph.
#
# stdout: "queued:<epic_id>" on success
# stderr: JSON error on failure (see Exit Codes in README.md)
#
# Exit codes: 0=success, 1=validation, 2=dependency, 3=I/O
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
epic_id=""
epic_path=""
priority="medium"
depends_on=""
queue_yaml=""
plan_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic-id)    epic_id="$2";    shift 2 ;;
    --epic-path)  epic_path="$2";  shift 2 ;;
    --priority)   priority="$2";   shift 2 ;;
    --depends-on) depends_on="$2"; shift 2 ;;
    --queue-yaml) queue_yaml="$2"; shift 2 ;;
    --plan-ref)   plan_ref="$2";   shift 2 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -z "$epic_id" ]]   && error_exit "Missing required argument: --epic-id" 1
[[ -z "$epic_path" ]] && error_exit "Missing required argument: --epic-path" 1
[[ -z "$queue_yaml" ]] && error_exit "Missing required argument: --queue-yaml" 1

# Validate epic-id format (must start with E-)
[[ ! "$epic_id" =~ ^E- ]] && error_exit "Invalid EPIC ID format: $epic_id (must start with E-)" 1

# Validate priority
case "$priority" in
  critical|high|medium|low) ;;
  *) error_exit "Invalid priority: $priority (must be critical, high, medium, or low)" 1 ;;
esac

# Validate queue-yaml parent directory is writable
queue_dir="$(dirname "$queue_yaml")"
if [[ -e "$queue_yaml" && ! -w "$queue_yaml" ]]; then
  error_exit "Queue file is not writable: $queue_yaml" 3
fi
if [[ ! -d "$queue_dir" ]]; then
  error_exit "Queue directory does not exist: $queue_dir" 3
fi
if [[ ! -w "$queue_dir" ]]; then
  error_exit "Queue directory is not writable: $queue_dir" 3
fi

# ---------------------------------------------------------------------------
# Step 1: Parse depends-on into an array
# ---------------------------------------------------------------------------
declare -a dep_array=()
if [[ -n "$depends_on" ]]; then
  IFS=',' read -ra dep_array <<< "$depends_on"
  # Trim whitespace from each element
  for i in "${!dep_array[@]}"; do
    dep_array[$i]="$(echo "${dep_array[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  done
fi

# ---------------------------------------------------------------------------
# Step 2: Read or create epic-queue.yaml
#
# We parse the YAML into a JSON array using awk so we can leverage jq for
# all validation logic (duplicate check, dep reference, cycle detection).
# ---------------------------------------------------------------------------

# parse_queue_to_json: read epic-queue.yaml, output JSON array of entries
# Each entry: {"epic_id":"...","status":"...","depends_on":["..."]}
parse_queue_to_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[]"
    return
  fi

  awk '
    # close_entry: finalize the current JSON entry before starting the next
    function close_entry() {
      if (!in_entry) return
      # If we were collecting multi-line depends_on items, close the array
      if (in_depends && !depends_closed) {
        if (dep_count > 0) printf "]"
        else printf "[]"
      }
      printf "}"
    }

    BEGIN {
      entry_count = 0
      in_entry = 0
      in_depends = 0
      depends_closed = 0
      dep_count = 0
      printf "["
    }

    # Skip comment lines and blank lines outside entries
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }

    # Detect start of a new queue entry (line starting with "  - epic_id:")
    /^[[:space:]]*-[[:space:]]+epic_id:/ {
      close_entry()
      in_entry = 1
      in_depends = 0
      depends_closed = 0
      dep_count = 0
      entry_count++
      if (entry_count > 1) printf ","

      # Extract epic_id value
      val = $0
      sub(/^[[:space:]]*-[[:space:]]+epic_id:[[:space:]]*/, "", val)
      gsub(/"/, "", val)
      sub(/[[:space:]]*$/, "", val)
      printf "{\"epic_id\":\"%s\"", val
      next
    }

    # Inside an entry, parse key-value fields
    in_entry && /^[[:space:]]+[a-z_]+:/ {
      # If we were in multi-line depends mode, close it before processing next key
      if (in_depends && !depends_closed) {
        if (dep_count > 0) printf "]"
        else printf "[]"
        depends_closed = 1
      }
      in_depends = 0

      line = $0
      # Strip leading whitespace
      sub(/^[[:space:]]+/, "", line)

      # Extract key
      colon_pos = index(line, ":")
      key = substr(line, 1, colon_pos - 1)
      val = substr(line, colon_pos + 1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      gsub(/"/, "", val)

      if (key == "status") {
        printf ",\"status\":\"%s\"", val
      } else if (key == "depends_on") {
        printf ",\"depends_on\":"
        in_depends = 1
        depends_closed = 0
        dep_count = 0

        # Check for inline array: depends_on: [] or depends_on: ["E-001"]
        if (val ~ /\[/) {
          # Inline array — parse items
          inner = val
          gsub(/[\[\]]/, "", inner)
          gsub(/"/, "", inner)
          sub(/^[[:space:]]+/, "", inner)
          sub(/[[:space:]]+$/, "", inner)
          if (inner == "") {
            # Empty array
            printf "[]"
          } else {
            printf "["
            n = split(inner, items, ",")
            for (i = 1; i <= n; i++) {
              sub(/^[[:space:]]+/, "", items[i])
              sub(/[[:space:]]+$/, "", items[i])
              if (items[i] != "") {
                if (dep_count > 0) printf ","
                printf "\"%s\"", items[i]
                dep_count++
              }
            }
            printf "]"
          }
          depends_closed = 1
          in_depends = 0
        }
        # If no bracket found, depends_on might have items on next lines (YAML list)
      }
      next
    }

    # Handle multi-line depends_on items: "    - E-001"
    in_entry && in_depends && !depends_closed && /^[[:space:]]*-[[:space:]]/ {
      val = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", val)
      gsub(/"/, "", val)
      sub(/[[:space:]]*$/, "", val)
      if (dep_count == 0) printf "["
      if (dep_count > 0) printf ","
      printf "\"%s\"", val
      dep_count++
      next
    }

    END {
      close_entry()
      printf "]"
    }
  ' "$file"
}

# Check if queue file exists; if not, we will create it
queue_exists=false
if [[ -f "$queue_yaml" ]]; then
  queue_exists=true
fi

# Parse existing entries into JSON
if $queue_exists; then
  queue_json="$(parse_queue_to_json "$queue_yaml")"
else
  queue_json="[]"
fi

# Ensure the JSON is valid (fallback to empty array)
if ! echo "$queue_json" | jq '.' >/dev/null 2>&1; then
  error_exit "Failed to parse existing queue file: $queue_yaml" 3
fi

# ---------------------------------------------------------------------------
# Step 3: Duplicate detection
#
# Check if epic_id already exists with status queued or running
# ---------------------------------------------------------------------------
duplicate="$(echo "$queue_json" | jq -r \
  --arg eid "$epic_id" \
  '[.[] | select(.epic_id == $eid and (.status == "queued" or .status == "running"))] | length'
)"

if [[ "$duplicate" -gt 0 ]]; then
  error_exit "Duplicate: EPIC $epic_id is already in the queue with status queued or running" 1
fi

# ---------------------------------------------------------------------------
# Step 4: Dependency validation
# ---------------------------------------------------------------------------
if [[ ${#dep_array[@]} -gt 0 ]]; then

  # 4a. Self-dependency check
  for dep in "${dep_array[@]}"; do
    if [[ "$dep" == "$epic_id" ]]; then
      error_exit "Self-dependency: $epic_id cannot depend on itself" 1
    fi
  done

  # 4b. Reference check — each dep must exist in queue (any status)
  all_ids="$(echo "$queue_json" | jq -r '.[].epic_id')"
  for dep in "${dep_array[@]}"; do
    if ! echo "$all_ids" | grep -qx "$dep"; then
      error_exit "Dependency $dep not found in queue. Add it first before adding $epic_id" 1
    fi
  done

  # 4c. Failed dependency warning
  for dep in "${dep_array[@]}"; do
    dep_status="$(echo "$queue_json" | jq -r \
      --arg d "$dep" \
      '.[] | select(.epic_id == $d) | .status'
    )"
    if [[ "$dep_status" == "failed" ]]; then
      echo "WARNING: Dependency $dep has status 'failed'" >&2
    fi
  done

  # 4d. Cycle detection via Kahn's algorithm
  #
  # Build the full graph: all non-removed entries + the new entry.
  # Use jq to add the new entry to the graph, then run Kahn's in awk.
  #
  # Format for awk: one line per node "node_id dep1,dep2,..." (empty deps = just node_id)

  # Build deps JSON for the new entry
  deps_json="$(printf '%s\n' "${dep_array[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"

  # Merge: existing entries (that have depends_on) + new entry
  # For entries without depends_on, treat as empty deps
  graph_lines="$(echo "$queue_json" | jq -r --arg eid "$epic_id" --argjson deps "$deps_json" '
    # Add depends_on:[] to entries missing it
    [.[] | if .depends_on == null then . + {"depends_on": []} else . end]
    # Exclude removed entries (we keep all others: queued, running, completed, failed)
    | [.[] | select(.status != "removed")]
    # Add the new entry
    | . + [{"epic_id": $eid, "depends_on": $deps, "status": "queued"}]
    # Output: epic_id<TAB>dep1,dep2,...
    | .[] | .epic_id + "\t" + (.depends_on | join(","))
  ')"

  # Run Kahn's algorithm in awk
  cycle_result="$(echo "$graph_lines" | awk -F'\t' '
    BEGIN {
      node_count = 0
    }
    {
      node = $1
      deps_str = $2

      # Register node
      if (!(node in node_idx)) {
        node_idx[node] = node_count
        nodes[node_count] = node
        in_degree[node_count] = 0
        node_count++
      }

      # Parse dependencies
      if (deps_str != "") {
        n = split(deps_str, deps, ",")
        for (i = 1; i <= n; i++) {
          dep = deps[i]
          if (dep == "") continue

          # Register dep node if not seen
          if (!(dep in node_idx)) {
            node_idx[dep] = node_count
            nodes[node_count] = dep
            in_degree[node_count] = 0
            node_count++
          }

          # Edge: dep -> node (node depends on dep)
          src = node_idx[dep]
          dst = node_idx[node]

          # Store adjacency: adj[src] = "dst1,dst2,..."
          if (src in adj) {
            adj[src] = adj[src] "," dst
          } else {
            adj[src] = dst ""
          }
          in_degree[dst]++
        }
      }
    }
    END {
      # BFS queue: start with nodes that have in_degree 0
      q_front = 0
      q_back = 0
      for (i = 0; i < node_count; i++) {
        if (in_degree[i] == 0) {
          queue[q_back++] = i
        }
      }

      processed = 0
      while (q_front < q_back) {
        curr = queue[q_front++]
        processed++

        # Process neighbors
        if (curr in adj) {
          n = split(adj[curr], neighbors, ",")
          for (i = 1; i <= n; i++) {
            nb = neighbors[i] + 0  # force numeric
            in_degree[nb]--
            if (in_degree[nb] == 0) {
              queue[q_back++] = nb
            }
          }
        }
      }

      if (processed < node_count) {
        # Cycle detected — report nodes still in cycle
        printf "CYCLE:"
        first = 1
        for (i = 0; i < node_count; i++) {
          if (in_degree[i] > 0) {
            if (!first) printf ","
            printf "%s", nodes[i]
            first = 0
          }
        }
        printf "\n"
      } else {
        printf "OK\n"
      }
    }
  ')"

  if [[ "$cycle_result" == CYCLE:* ]]; then
    cycle_members="${cycle_result#CYCLE:}"
    error_exit "Circular dependency detected among: $cycle_members" 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 5: Build the new queue entry YAML block
# ---------------------------------------------------------------------------
timestamp="$(iso_timestamp)"

# Format depends_on as YAML
if [[ ${#dep_array[@]} -eq 0 ]]; then
  depends_yaml="[]"
else
  depends_yaml="["
  for i in "${!dep_array[@]}"; do
    if [[ $i -gt 0 ]]; then
      depends_yaml+=", "
    fi
    depends_yaml+="\"${dep_array[$i]}\""
  done
  depends_yaml+="]"
fi

# Format plan_ref
if [[ -n "$plan_ref" ]]; then
  plan_ref_yaml="\"$plan_ref\""
else
  plan_ref_yaml="null"
fi

# Build the entry block
new_entry="$(cat <<ENTRY

  - epic_id: "$epic_id"
    path: "$epic_path"
    priority: $priority
    status: queued
    depends_on: $depends_yaml
    added_at: "$timestamp"
    started_at: null
    completed_at: null
    plan_ref: $plan_ref_yaml
ENTRY
)"

# ---------------------------------------------------------------------------
# Step 6: Write the queue file atomically (temp file + mv)
# ---------------------------------------------------------------------------
tmp_file="${queue_yaml}.tmp.$$"

# Trap to clean up temp file on unexpected exit
trap 'rm -f "$tmp_file"' EXIT

if $queue_exists; then
  # Read existing file content
  existing_content="$(cat "$queue_yaml")"

  # Update last_modified timestamp
  # Use sed to replace the last_modified line
  updated_content="$(echo "$existing_content" | sed "s|^last_modified:.*|last_modified: \"$timestamp\"|")"

  # Append the new entry at the end
  printf '%s\n%s\n' "$updated_content" "$new_entry" > "$tmp_file"
else
  # Create brand new queue file
  cat > "$tmp_file" <<NEWQUEUE
# Epic Queue — managed by Orchestrator + /epic-queue command
# Do not edit manually while an EPIC is running.

paused: false
last_modified: "$timestamp"

queue:
$new_entry
NEWQUEUE
fi

# Atomic rename
mv "$tmp_file" "$queue_yaml" || error_exit "Failed to write queue file: $queue_yaml" 3

# ---------------------------------------------------------------------------
# Step 7: Output confirmation
# ---------------------------------------------------------------------------
echo "queued:${epic_id}"
