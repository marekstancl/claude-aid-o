#!/usr/bin/env bash
# audit-watchdog.sh — nezávislá pojistka pro běžící /aid-audit-tests.
#
# Každou minutu udělá inkrementální kopii adresáře auditu mimo auditovaný
# strom a hlásí, když z něj něco zmizí. Nespoléhá na nic v pluginu — přesně
# proto, že příčina toho mizení není známá.
#
# Použití:  bash audit-watchdog.sh <cesta-k-projektu>
set -uo pipefail
PROJ="${1:?zadej cestu k auditovanému projektu}"
AUD="$PROJ/.aid-o/work/test-audits"
BAK="${AUDIT_WATCHDOG_BACKUP:-$HOME/aid-audit-backups/$(basename "$PROJ")}"
mkdir -p "$BAK"

echo "watchdog: hlídám $AUD"
echo "watchdog: zálohy do $BAK"
echo "watchdog: ukonči Ctrl-C, až audit doběhne"
echo

prev=""
while true; do
  if [ -d "$AUD" ]; then
    cur="$(cd "$AUD" && find . -type f 2>/dev/null | LC_ALL=C sort)"
    n="$(printf '%s' "$cur" | grep -c . || true)"

    if [ -n "$prev" ]; then
      lost="$(comm -23 <(printf '%s\n' "$prev") <(printf '%s\n' "$cur") | grep -v '^$' || true)"
      if [ -n "$lost" ]; then
        echo "!!! $(date +%H:%M:%S) ZMIZELY SOUBORY:"
        printf '%s\n' "$lost" | sed 's|^\./|      |'
        echo "    obnovuju ze zálohy…"
        cp -a "$BAK/." "$AUD/" 2>/dev/null \
          && echo "    OBNOVENO — audit může pokračovat" \
          || echo "    OBNOVA SELHALA, záloha je v $BAK"
      fi
    fi

    # rsync-like inkrement bez rsync
    cp -a "$AUD/." "$BAK/" 2>/dev/null
    printf '\r%s  souborů: %-6s  záloha OK ' "$(date +%H:%M:%S)" "$n"
    prev="$cur"
  else
    printf '\r%s  (adresář auditu zatím neexistuje) ' "$(date +%H:%M:%S)"
  fi
  sleep 60
done
