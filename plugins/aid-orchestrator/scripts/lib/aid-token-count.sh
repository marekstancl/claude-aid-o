#!/usr/bin/env bash
# aid-token-count.sh — Token estimation from character count
# Usage: count_tokens <file_or_text> [content_type: prose|code|mixed]
# Stdout: JSON {"estimated_tokens":N,"char_count":N,"content_type":"...","ratio":N}

count_tokens() {
  local input="$1"
  local content_type="${2:-mixed}"

  # Determine character count
  local char_count
  if [[ -f "$input" ]]; then
    char_count=$(wc -c < "$input")
  else
    char_count=${#input}
  fi

  # Content-type ratios (chars per token):
  # prose: ~4.0 (English text, GPT-4 empirical)
  # code: ~3.0 (more symbols, shorter tokens)
  # mixed: ~3.5 (skills/agents = prose + code)
  local ratio
  case "$content_type" in
    prose) ratio="4.0" ;;
    code)  ratio="3.0" ;;
    mixed) ratio="3.5" ;;
    *)     ratio="3.5"; content_type="mixed" ;;  # unknown = mixed
  esac

  local estimated_tokens
  estimated_tokens=$(awk "BEGIN {printf \"%d\", int($char_count / $ratio + 0.5)}")

  echo "{\"estimated_tokens\":${estimated_tokens},\"char_count\":${char_count},\"content_type\":\"${content_type}\",\"ratio\":${ratio}}"
  return 0
}

# Allow direct invocation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  count_tokens "${1:?Usage: aid-token-count.sh <file_or_text> [content_type]}" "${2:-mixed}"
fi

export -f count_tokens
