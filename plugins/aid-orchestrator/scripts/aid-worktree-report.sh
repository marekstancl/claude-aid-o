#!/usr/bin/env bash
# =============================================================================
# aid-worktree-report.sh — which git worktrees is somebody going to clean up,
# and which will live forever?
#
# WHY THIS EXISTS, precisely — because the first version of this finding was
# WRONG and the correction is the whole point. AID does tear down the worktree
# it creates: `_pfsm_teardown_worktree` in aid-plan-fsm.sh is a careful,
# locked, idempotent teardown that deliberately deletes NOTHING when it cannot
# take the lock, because a concurrent repair may be creating the tree. That
# part works.
#
# What nobody owns is everything created OUTSIDE the canonical path
# `<root>/.aid-worktrees/plan-<plan_id>`:
#
#   • trees made by hand or by an older convention — on 2026-08-11 two such
#     siblings sat in /opt/eco/projects/ since 2 and 10 August, both with
#     merged branches and nothing uncommitted;
#   • the frozen CP3 copies — `cp3-frozen` appears in NO script and NO skill
#     of this plugin. They exist because CP3 requires two reviews to agree on
#     one commit, which a live branch cannot offer, so a controller freezes a
#     tree by hand. An established practice with no mechanism, therefore no
#     cleanup.
#
# And it is not merely disk. On 2026-08-11 an orphaned copy took down a suite:
# `aid-test-adapter-shell-suite` scans the real repository, found copies of the
# suites under `.aid-worktrees/`, and refused them for the dot in the path —
# killing discovery for the whole portfolio. A second window with a plan
# checked out was enough to turn the merge path red.
#
# THIS TOOL REPORTS, IT DOES NOT DELETE. Deleting a foreign worktree
# automatically is dangerous — the frozen CP3 trees are review EVIDENCE, and a
# tree this tool cannot classify may be somebody's live work. Automatic
# removal stays where it belongs: with the code that created the tree and knows
# it is finished.
#
# Usage: aid-worktree-report.sh [--root <repo>] [--stale-days N] [--json]
# Exit:  0 always when the report was produced — a finding is not a failure of
#        the reporter (the same rule the CI runner watchdog learned the hard
#        way). Non-zero only when the report could not be produced at all.
# =============================================================================
set -uo pipefail

ROOT=""
STALE_DAYS="${AID_WORKTREE_STALE_DAYS:-7}"
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --json) AS_JSON=1; shift ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not a git repository and no --root given" >&2; exit 2; }

MAIN_ROOT="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
  echo "ERROR: cannot resolve the git common dir for $ROOT" >&2; exit 2; }
MAIN_ROOT="${MAIN_ROOT%/.git}"

default_branch="main"
git -C "$MAIN_ROOT" show-ref --verify --quiet refs/heads/main || default_branch="master"

now_epoch="$(date +%s)"
rows=()

# `git worktree list --porcelain` emits blank-line-separated records.
while IFS= read -r line; do
  case "$line" in
    worktree\ *) wt="${line#worktree }" ;;
    branch\ *)   br="${line#branch refs/heads/}" ;;
    detached)    br="(detached)" ;;
    "")
      [[ -n "${wt:-}" ]] || continue
      # --- classify -------------------------------------------------------
      kind="" note=""
      if [[ "$wt" == "$MAIN_ROOT" ]]; then
        kind="main"; note="hlavni checkout"
      elif [[ "$wt" == "$MAIN_ROOT/.aid-worktrees/plan-"* ]]; then
        kind="owned"; note="AID ji vytvoril a pri plan-close ji sam odstrani"
      elif [[ "$wt" == *"/.aid-worktrees/cp3-frozen-"* ]]; then
        kind="frozen"; note="zmrazena kopie pro CP3 — DUKAZ, nemazat automaticky; zadny mechanismus ji neuklidi"
      else
        kind="foreign"; note="mimo kanonickou cestu — AID o ni nevi a nikdy ji neuklidi"
      fi

      # --- age + merge state ---------------------------------------------
      age_days=""
      if [[ -d "$wt" ]]; then
        mtime="$(stat -c %Y "$wt" 2>/dev/null || echo "$now_epoch")"
        age_days=$(( (now_epoch - mtime) / 86400 ))
      fi
      merged="?"
      if [[ "$br" != "(detached)" && -n "${br:-}" ]]; then
        if git -C "$MAIN_ROOT" branch --merged "$default_branch" --list "$br" 2>/dev/null | grep -q .; then
          merged="ano"
        else
          merged="ne"
        fi
      fi
      dirty="?"
      if [[ -d "$wt" ]]; then
        dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l)"
      fi

      # --- is it stale? ----------------------------------------------------
      # Stale = nobody will clean it AND it is finished AND it has sat there.
      # `owned` is never stale: its teardown is somebody's job and it happens.
      # `frozen` goes stale on age alone — it is evidence, and evidence has a
      # shelf life; it is never "finished" by a merged branch because it is a
      # detached head.
      stale="ne"
      case "$kind" in
        foreign)
          [[ "$merged" == "ano" && "${dirty:-1}" -eq 0 && "${age_days:-0}" -ge "$STALE_DAYS" ]] && stale="ano" ;;
        frozen)
          [[ "${age_days:-0}" -ge "$STALE_DAYS" ]] && stale="ano" ;;
      esac

      rows+=("${kind}|${wt}|${br:-?}|${merged}|${dirty}|${age_days:-?}|${stale}|${note}")
      wt=""; br=""
      ;;
  esac
done < <(git -C "$MAIN_ROOT" worktree list --porcelain; echo)

stale_count=0
for r in "${rows[@]}"; do
  IFS='|' read -r kind wt br merged dirty age stale note <<<"$r"
  [[ "$stale" == "ano" ]] && stale_count=$((stale_count + 1))
done

if [[ "$AS_JSON" -eq 1 ]]; then
  printf '{"stale_days":%s,"stale_count":%s,"worktrees":[' "$STALE_DAYS" "$stale_count"
  first=1
  for r in "${rows[@]}"; do
    IFS='|' read -r kind wt br merged dirty age stale note <<<"$r"
    [[ "$first" -eq 1 ]] || printf ','
    first=0
    printf '{"kind":"%s","path":"%s","branch":"%s","merged":"%s","dirty":%s,"age_days":%s,"stale":"%s"}' \
      "$kind" "$wt" "$br" "$merged" "${dirty:-0}" "${age:-0}" "$stale"
  done
  printf ']}\n'
  exit 0
fi

printf '%-8s %-11s %-7s %-6s %-5s %s\n' "DRUH" "VETEV" "SLITA" "ZMENY" "DNI" "CESTA"
for r in "${rows[@]}"; do
  IFS='|' read -r kind wt br merged dirty age stale note <<<"$r"
  mark=""; [[ "$stale" == "ano" ]] && mark=" ← K UKLIZENI"
  printf '%-8s %-11s %-7s %-6s %-5s %s%s\n' \
    "$kind" "${br:0:11}" "$merged" "${dirty}" "${age}" "$wt" "$mark"
done

echo "---"
if [[ "$stale_count" -eq 0 ]]; then
  echo "aid-worktree-report: ${#rows[@]} kopii, zadna k uklizeni (prah ${STALE_DAYS} dni)."
else
  echo "aid-worktree-report: ${#rows[@]} kopii, ${stale_count} k uklizeni (prah ${STALE_DAYS} dni)."
  echo
  echo "Co s tim — TENTO NASTROJ NIC NEMAZE, rozhodnuti je na cloveku:"
  echo "  foreign  git worktree remove --force <cesta> ; git worktree prune"
  echo "           (nejdriv overit: slita vetev, nula zmen — sloupce vyse)"
  echo "  frozen   dukazni material CP3. Smazat az kdyz uz plan nikdo nereviduje;"
  echo "           dokud lezi, prohledavani repozitare v nem najde kopie sad."
fi
exit 0
