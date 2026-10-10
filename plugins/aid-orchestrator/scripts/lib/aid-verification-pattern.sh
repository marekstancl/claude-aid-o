#!/usr/bin/env bash
# =============================================================================
# lib/aid-verification-pattern.sh — the ONE reader and validator of
# `- [ ] AC<n>:` criteria and their `verification_pattern` blocks (P109 Step 1)
#
#   _aid_vp_parse_ac <file> <heading-ere> [--lines]
#       One record per criterion under every `## <heading>` the ERE matches,
#       fields separated by ASCII Unit Separator (0x1F):
#         label, text, type, cmd, file, regex, expected_exit
#       A criterion with no block has type `no_verification`. With --lines two
#       more fields: the criterion's line and the block's opening line (0 = none).
#   _aid_vp_extract <file>
#       Every fenced block holding `verification_pattern:` anywhere in the file,
#       as "<line>\t<record>" (label and text empty) — the shape A6 checks.
#   _aid_vp_validate <record>
#       The #20 / A6 rules on one record: a known type, the keys that type
#       needs, no `<…>` or `{…}` placeholder in cmd/file/regex/expected_exit.
#       Prints one message per violation; exit 1 when there is any.
#
# WHY: three readers of the same grammar (the runner aid-plan-diff.sh, the plan
# check's A6, the brief lint) would drift; a criterion one of them accepts must
# be read the same way by the one that runs it. The awk below was moved here
# from aid-plan-diff.sh unchanged; A6's rules from aid-plan-check.sh.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_VP_SH_LOADED:-}" ]] && return 0
_AID_VP_SH_LOADED=1

# Shared awk functions: value extraction of one `key: value` line.
# Portable awk (mawk-compatible) — no gensub().
_AID_VP_AWK_FUNCS='
    function extract_label(s,   tmp) {
      tmp = s
      sub(/^- \[[ x]\] /, "", tmp)
      sub(/:.*$/, "", tmp)
      return tmp
    }
    function extract_text(s,   tmp) {
      tmp = s
      sub(/^- \[[ x]\] AC[0-9]+: */, "", tmp)
      return tmp
    }
    function extract_text_role(s,   tmp) {
      tmp = s
      sub(/^- \[[ x]\] \[[a-z_]+\] */, "", tmp)
      return tmp
    }
    function extract_yaml_val(s, key,   tmp, prefix) {
      tmp = s
      prefix = ".*" key ":[[:space:]]*"
      sub(prefix, "", tmp)
      sub(/^"/, "", tmp)
      sub(/"[[:space:]]*$/, "", tmp)
      sub(/[[:space:]]+$/, "", tmp)
      # Unescape YAML double-quoted-scalar escapes: \" -> " and \\ -> \ (a cmd
      # with nested quoting is handed to eval; literal backslashes corrupt it).
      # Protect a literal double backslash first so \\\" is not misread.
      gsub(/\\\\/, "\001", tmp)
      gsub(/\\"/, "\"", tmp)
      gsub(/\001/, "\\", tmp)
      return tmp
    }
    function take(line) {
      if (line ~ /type:/)          ac_type=extract_yaml_val(line, "type")
      if (line ~ /cmd:/)           ac_cmd=extract_yaml_val(line, "cmd")
      if (line ~ /file:/)          ac_file=extract_yaml_val(line, "file")
      if (line ~ /regex:/)         ac_regex=extract_yaml_val(line, "regex")
      if (line ~ /expected_exit:/) ac_expected_exit=extract_yaml_val(line, "expected_exit")
    }
'

_aid_vp_parse_ac() {
  local file="$1" sec="$2" lines=0
  [[ "${3:-}" == "--lines" ]] && lines=1
  awk -v US=$'\x1f' -v sec="$sec" -v lines="$lines" "$_AID_VP_AWK_FUNCS"'
    function emit(t) {
      if (ac_label == "") return
      printf "%s%s%s%s%s%s%s%s%s%s%s%s%s", ac_label, US, ac_text, US, t, US, ac_cmd, US, ac_file, US, ac_regex, US, ac_expected_exit
      if (lines) printf "%s%s%s%s", US, ac_line, US, blk_line
      printf "\n"
      ac_flushed=1
    }
    function flush_no_verify() {
      if (ac_label != "" && !ac_flushed) {
        ac_cmd=""; ac_file=""; ac_regex=""; ac_expected_exit="0"; blk_line=0
        emit("no_verification")
      }
    }
    # Section flag: on at a matching `## ` heading, off at the next `## `.
    # (A start/end range pattern collapses when the heading itself would match
    # the terminator — the flag form has no such collision.)
    # A new section, or a bullet that is no criterion, ends the criterion before
    # it: a block under an unlabelled bullet belongs to no criterion (it used to
    # overwrite the criterion before it).
    $0 ~ ("^## (" sec ")") { flush_no_verify(); ac_label=""; in_yaml=0; f=1; next }
    /^## / { f=0 }
    f && /^- / && $0 !~ /^- \[[ x]\] AC[0-9]+:/ && $0 !~ /^- \[[ x]\] \[[a-z_]+\]/ { flush_no_verify(); ac_label=""; in_yaml=0; next }
    f {
      if ($0 ~ /^- \[[ x]\] AC[0-9]+:/ || $0 ~ /^- \[[ x]\] \[[a-z_]+\]/) {
        flush_no_verify()
        ac_label=extract_label($0)
        if ($0 ~ /^- \[[ x]\] AC[0-9]+:/) ac_text=extract_text($0)
        else                              ac_text=extract_text_role($0)
        in_yaml=0; ac_flushed=0; ac_line=NR; blk_line=0
        ac_type=""; ac_cmd=""; ac_file=""; ac_regex=""; ac_expected_exit="0"
      }
      if ($0 ~ /^[[:space:]]*```yaml/) { in_yaml=1; if (!blk_line) blk_line=NR; next }
      if ($0 ~ /^[[:space:]]*```$/ && in_yaml) {
        in_yaml=0
        if (ac_type != "") emit(ac_type)
        next
      }
      if (in_yaml) take($0)
    }
    END { flush_no_verify() }
  ' "$file"
}

_aid_vp_extract() {
  # Read from the RAW file: the blocks live inside fences.
  awk -v US=$'\x1f' "$_AID_VP_AWK_FUNCS"'
    /verification_pattern:/ { inside = 1; start = NR; ac_type=""; ac_cmd=""; ac_file=""; ac_regex=""; ac_expected_exit="0"; next }
    inside && /^[[:space:]]*```/ {
      printf "%s\t%s%s%s%s%s%s%s%s%s%s%s%s%s\n", start, "", US, "", US, ac_type, US, ac_cmd, US, ac_file, US, ac_regex, US, ac_expected_exit
      inside = 0; next
    }
    inside { take($0) }
  ' "$1"
}

_aid_vp_validate() {
  local label text type cmd file regex xexit bad=0
  IFS=$'\x1f' read -r label text type cmd file regex xexit _ <<< "$1"
  case "$type" in
    cmd)            [[ -n "$cmd" ]] || { echo "verification_pattern type cmd without cmd:"; bad=1; } ;;
    must_not_exist) [[ -n "$file" ]] || { echo "verification_pattern type must_not_exist without file:"; bad=1; } ;;
    must_contain)   [[ -n "$file" && -n "$regex" ]] || { echo "verification_pattern type must_contain needs file: and regex:"; bad=1; } ;;
    *)              echo "verification_pattern type '${type:-<missing>}' is not one of cmd | must_not_exist | must_contain"; bad=1 ;;
  esac
  if printf '%s\n' "$cmd" "$file" "$regex" "$xexit" | grep -qE '<[A-Za-z_ -]+>|\{[A-Za-z_ -]+\}'; then
    echo "verification_pattern carries a placeholder (<...> or {...})"; bad=1
  fi
  return "$bad"
}
