#!/usr/bin/env bash
# =============================================================================
# lib/aid-worktree-env.sh — what a new plan or step worktree needs that git does not carry (AID 3.13.0)
#
#   aid_worktree_env_prepare <source checkout> <new tree> <state root>
#   aid_worktree_env_record_path <state root> <tree>        .aid-o/work/worktree-env/<tree name>.json
#
# `.aid-o/config/project.yaml`:
#   worktree.copy_untracked: [".env", …]   ignored, untracked files copied from the source checkout (never over an
#                                          existing file; a path that climbs out, a symlink, a tracked or a not
#                                          ignored source is refused)
#   worktree.setup: ["cd ui && npm ci --prefer-offline", …]   commands run IN the new tree after it is created — the
#                                          tree gets its own dependencies; nothing is shared with the source checkout
# Both default to []: nothing happens. One record per tree path, replaced when the tree is created again: a new tree
# is a new environment, and the record describes the tree under review (older generations are not kept on purpose). A failing setup command does not stop the run: the record says which, and the
# step check names it. WAN P114 26. 10. and P116 28. 10. 2026: step trees had no .env and an empty ui/node_modules;
# agents copied .env by hand and a brief point came out `absent` for the environment alone.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_WORKTREE_ENV_SH_LOADED:-}" ]] && return 0
_AID_WORKTREE_ENV_SH_LOADED=1

# keyed by the tree's canonical path (two trees with one directory name never share a record)
aid_worktree_env_record_path() {
  printf '%s/.aid-o/work/worktree-env/%s-%s.json' "$1" "$(basename "$2")" "$(realpath -m -- "$2" | sha256sum | cut -c1-12)"
}

aid_worktree_env_prepare() {
  local src="$1" tree="$2" sroot="$3" cfg p rec copies='[]' setups='[]' cmd rc t0 log
  cfg="${sroot}/.aid-o/config/project.yaml"
  local -a cp_list=() su_list=()
  if [[ -f "$cfg" ]]; then
    mapfile -t cp_list < <(yq -r '(.worktree.copy_untracked // [])[]' "$cfg" 2>/dev/null)
    # one array element = one command, newlines and all (a YAML block `cd ui` + `npm ci` stays one shell)
    while IFS= read -r -d '' cmd; do su_list+=("$cmd"); done < <(yq -o=json '(.worktree.setup // [])' "$cfg" 2>/dev/null | jq -j '.[] | tostring, "\u0000"' 2>/dev/null)
  fi
  rec="$(aid_worktree_env_record_path "$sroot" "$tree")"
  if (( ${#cp_list[@]} + ${#su_list[@]} == 0 )); then
    # nothing named: no record — and an old one of a tree at this path (created before the keys were removed) goes
    rm -f "$rec" "${rec%.json}".setup-*.log 2>/dev/null; return 0
  fi
  local rs rt; rs="$(realpath -m -- "$src")"; rt="$(realpath -m -- "$tree")"
  _wte_copy() {  # <path> — prints the outcome word
    local p="$1"
    [[ -n "$p" && "$p" != /* && "$p" != *..* ]] || { echo "refused: not a relative path inside the repository"; return; }
    [[ "$(realpath -m -- "${rs}/${p}")" == "${rs}/${p}" && "$(realpath -m -- "${rt}/${p}")" == "${rt}/${p}" ]] \
      || { echo "refused: the path leads out through a symlink"; return; }
    [[ -e "${rs}/${p}" ]] || { echo "skipped: not in the source checkout"; return; }
    [[ -f "${rs}/${p}" && ! -L "${rs}/${p}" ]] || { echo "refused: not a plain file"; return; }
    ! git -C "$rs" ls-files --error-unmatch -- "$p" >/dev/null 2>&1 || { echo "refused: tracked — git carries it"; return; }
    git -C "$rs" check-ignore -q -- "$p" 2>/dev/null || { echo "refused: not ignored (it would show as a new file in the tree)"; return; }
    [[ ! -e "${rt}/${p}" && ! -L "${rt}/${p}" ]] || { echo "skipped: already in the tree (never overwritten)"; return; }
    # every component is opened relative to its parent with O_NOFOLLOW: no directory or file swapped for a symlink
    # between the checks and the copy is followed, and the destination is created exclusively (never overwritten)
    python3 -c '
import os, sys, shutil
src_root, dst_root, rel = sys.argv[1], sys.argv[2], sys.argv[3]
parts = rel.split("/")
D = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
def walk(root, create):
    fd = os.open(root, D)
    for name in parts[:-1]:
        if create:
            try: os.mkdir(name, 0o755, dir_fd=fd)
            except FileExistsError: pass
        nfd = os.open(name, D, dir_fd=fd); os.close(fd); fd = nfd
    return fd
sd = walk(src_root, False); dd = walk(dst_root, True)
fi = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=sd)
st = os.fstat(fi)
fo = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, st.st_mode & 0o777, dir_fd=dd)
with os.fdopen(fi, "rb") as a, os.fdopen(fo, "wb") as b: shutil.copyfileobj(a, b)
' "$rs" "$rt" "$p" 2>/dev/null && echo copied || echo "failed: copy (the file changed during the copy, or the tree already has it)"
  }
  for p in "${cp_list[@]}"; do
    copies="$(jq -c --arg p "$p" --arg o "$(_wte_copy "$p")" '. + [{path: $p, outcome: $o}]' <<< "$copies")"
  done
  mkdir -p "$(dirname "$rec")"; rm -f "${rec%.json}".setup-*.log 2>/dev/null
  for cmd in "${su_list[@]}"; do
    [[ -n "$cmd" ]] || continue
    log="${rec%.json}.setup-$(( $(jq 'length' <<< "$setups") + 1 )).log"; t0=$(date +%s); rc=0
    ( cd "$rt" && timeout -k 10 "${AID_WORKTREE_SETUP_TIMEOUT:-900}" bash -c "$cmd" ) > "$log" 2>&1 || rc=$?
    setups="$(jq -c --arg c "$cmd" --argjson rc "$rc" --argjson d "$(( $(date +%s) - t0 ))" --arg l "$log" \
      '. + [{command: $c, exit: $rc, duration_s: $d, log: $l}]' <<< "$setups")"
    (( rc == 0 )) || echo "worktree: setup failed in ${tree} (exit ${rc}): ${cmd} — log ${log}" >&2
  done
  jq -n --arg t "$rt" --arg s "$rs" --argjson c "$copies" --argjson u "$setups" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{tree: $t, source: $s, copies: $c, setup: $u, at: $at}' > "$rec"
  jq -r '.copies[] | select(.outcome != "copied") | "worktree: \(.path) \(.outcome)"' "$rec" >&2
  return 0
}
