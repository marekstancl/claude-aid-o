#!/usr/bin/env bash
# =============================================================================
# aid-plan-graph.sh — Shared lib: dependency graph builder with Kahn topo-sort
#
# Provides: build_plan_graph <step_ids_nl> <edges_nl>
#
# Usage (sourced):
#   source lib/aid-plan-graph.sh
#   result="$(build_plan_graph "$step_ids_nl" "$edges_nl")"
#
# Requirements: bash 4.0+, jq, awk
# =============================================================================

# ---------------------------------------------------------------------------
# Guard: must be sourced, not executed directly.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: aid-plan-graph.sh must be sourced, not executed directly." >&2
  echo "Usage: source \"\$(dirname \"\$0\")/lib/aid-plan-graph.sh\"" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# build_plan_graph <step_ids_nl> <edges_nl>
#
# Arguments:
#   step_ids_nl  — newline-joined step IDs (e.g. "step_1_backend\nstep_2_qa\n")
#   edges_nl     — newline-joined "from->to" edges (e.g. "step_1_backend->step_2_qa\n")
#
# Output (stdout): JSON object
#   {
#     "edges":             [ {"before": "...", "after": "..."}, ... ],
#     "topological_order": [ "step_id", ... ],   -- empty [] if cycles
#     "cycles":            [ "step_id", ... ]    -- empty [] if no cycles
#   }
#
# Exit codes:
#   0 — success (acyclic graph, or graph with cycles — cycles field is populated)
#   1 — bad input (empty step_ids_nl)
# ---------------------------------------------------------------------------
build_plan_graph() {
  local step_ids_nl="$1"
  local edges_nl="${2:-}"

  # Validate: step_ids_nl must be non-empty
  if [[ -z "$step_ids_nl" ]]; then
    echo '{"error":"build_plan_graph: step_ids_nl is empty"}' >&2
    return 1
  fi

  # Build edges JSON array: [ {"before": "from", "after": "to"}, ... ]
  local edges_json="[]"
  if [[ -n "$edges_nl" ]]; then
    while IFS= read -r edge; do
      [[ -z "$edge" ]] && continue
      local from="${edge%%->*}"
      local to="${edge##*->}"
      [[ -z "$from" || -z "$to" ]] && continue
      edges_json="$(printf '%s' "$edges_json" | jq \
        --arg b "$from" \
        --arg a "$to" \
        '. + [{"before": $b, "after": $a}]')"
    done <<< "$edges_nl"
  fi

  # Run Kahn's algorithm in awk
  # Determinism: sort each wave of in-degree-0 nodes lexicographically before
  # adding to the queue, so that 2× runs on the same input produce identical
  # topological_order output.
  local kahn_result
  kahn_result="$(awk \
    -v step_ids_nl="$step_ids_nl" \
    -v edges_nl="$edges_nl" \
    'BEGIN {
      # Parse step IDs (newline-separated)
      n = split(step_ids_nl, steps, "\n")
      # Remove empty entries and build exists map
      valid_n = 0
      for (i = 1; i <= n; i++) {
        s = steps[i]
        # trim whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        if (s == "") continue
        valid_n++
        valid_steps[valid_n] = s
        in_degree[s] = 0
        exists[s] = 1
      }
      n = valid_n

      # Parse edges (newline-separated "from->to")
      m = split(edges_nl, edge_arr, "\n")
      edge_count = 0
      for (i = 1; i <= m; i++) {
        e = edge_arr[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", e)
        if (e == "") continue
        split(e, parts, "->")
        from = parts[1]
        to   = parts[2]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", from)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", to)
        if (from == "" || to == "") continue
        edge_count++
        adj[edge_count] = from "|" to
        in_degree[to]++
      }

      # Collect initial zero-in-degree nodes, sort them lexicographically
      zero_count = 0
      for (i = 1; i <= n; i++) {
        s = valid_steps[i]
        if (in_degree[s] == 0) {
          zero_nodes[++zero_count] = s
        }
      }
      # Sort lexicographically (insertion sort — n is small)
      for (i = 2; i <= zero_count; i++) {
        key = zero_nodes[i]
        j = i - 1
        while (j >= 1 && zero_nodes[j] > key) {
          zero_nodes[j+1] = zero_nodes[j]
          j--
        }
        zero_nodes[j+1] = key
      }

      # Load sorted zero-degree nodes into queue
      queue_head = 0
      queue_tail = 0
      for (i = 1; i <= zero_count; i++) {
        queue[queue_tail++] = zero_nodes[i]
      }

      # Process queue — Kahn BFS
      topo_count = 0
      while (queue_head < queue_tail) {
        node = queue[queue_head++]
        topo_order[++topo_count] = node

        # Collect newly zero-degree neighbors
        new_zero_count = 0
        for (i = 1; i <= edge_count; i++) {
          split(adj[i], parts, "|")
          if (parts[1] == node) {
            in_degree[parts[2]]--
            if (in_degree[parts[2]] == 0) {
              new_zero[++new_zero_count] = parts[2]
            }
          }
        }

        # Sort newly zero-degree nodes lexicographically before enqueuing
        for (i = 2; i <= new_zero_count; i++) {
          key = new_zero[i]
          j = i - 1
          while (j >= 1 && new_zero[j] > key) {
            new_zero[j+1] = new_zero[j]
            j--
          }
          new_zero[j+1] = key
        }
        for (i = 1; i <= new_zero_count; i++) {
          queue[queue_tail++] = new_zero[i]
        }
        delete new_zero
        new_zero_count = 0
      }

      # Check for cycles: any node not processed has in_degree > 0
      if (topo_count < n) {
        cycle_nodes = ""
        for (i = 1; i <= n; i++) {
          s = valid_steps[i]
          if (in_degree[s] > 0) {
            if (cycle_nodes != "") cycle_nodes = cycle_nodes "\n"
            cycle_nodes = cycle_nodes s
          }
        }
        print "CYCLE:" cycle_nodes
      } else {
        # Print topological order — one per line
        for (i = 1; i <= topo_count; i++) {
          print "TOPO:" topo_order[i]
        }
      }
    }')"

  # Parse kahn_result into JSON
  local topo_json="[]"
  local cycles_json="[]"

  if echo "$kahn_result" | grep -q "^CYCLE:"; then
    # Cycle detected — build cycles array from node names after "CYCLE:" prefix
    local cycle_block
    cycle_block="$(echo "$kahn_result" | sed 's/^CYCLE://')"
    while IFS= read -r node; do
      node="$(echo "$node" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$node" ]] && continue
      cycles_json="$(printf '%s' "$cycles_json" | jq --arg n "$node" '. + [$n]')"
    done <<< "$cycle_block"
    # topological_order stays []
  else
    # Acyclic — build topo array
    while IFS= read -r line; do
      [[ "$line" != TOPO:* ]] && continue
      local node="${line#TOPO:}"
      node="$(echo "$node" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$node" ]] && continue
      topo_json="$(printf '%s' "$topo_json" | jq --arg n "$node" '. + [$n]')"
    done <<< "$kahn_result"
  fi

  # Emit JSON result
  printf '%s' "$edges_json" | jq \
    --argjson topo "$topo_json" \
    --argjson cycles "$cycles_json" \
    '{"edges": ., "topological_order": $topo, "cycles": $cycles}'
}
