# P113 test helper: accepted place verdicts for studio suites that are not about the places.
# A project made by `aid-ui-state.sh init` goes through the decision places (places: true), so build-record needs the
# motion verdict and an accepting answer of a place's question that place's verdict. The verdicts are made once per
# file the honest way (tests/lib/aid-ui-place-ok.py: frozen critic, a round, place-verdict, place-record) in a
# template project and copied into each test's project with the files they were decided over; place_ok decides a
# place inside the test's own project (web: over its own site).
places_template() {   # setup_file: struktura, sdeleni, logo, pohyb, vzhled decided in $BATS_FILE_TMPDIR/places
  PLACES_TPL="$BATS_FILE_TMPDIR/places"; export PLACES_TPL
  [[ -f "$PLACES_TPL/docs/design/brand-state.json" ]] && return 0
  mkdir -p "$PLACES_TPL"
  bash "$BATS_TEST_DIRNAME/../../aid-ui-state.sh" init "$PLACES_TPL" >/dev/null
  python3 "$BATS_TEST_DIRNAME/../lib/aid-ui-place-ok.py" "$PLACES_TPL" vzhled >/dev/null
}
places_copy() {   # places_copy <project>: the template's verdicts and the inputs they stand on
  local p="$1" s="$1/docs/design/brand-state.json"
  mkdir -p "$p/.aid-ui"
  cp -r "$PLACES_TPL/.aid-ui/critic" "$PLACES_TPL/.aid-ui/logo" "$PLACES_TPL/.aid-ui/motion" "$PLACES_TPL/.aid-ui/directions" \
    "$PLACES_TPL/.aid-ui/structure.json" "$p/.aid-ui/"
  jq --argjson v "$(jq -c .place_verdicts "$PLACES_TPL/docs/design/brand-state.json")" '.place_verdicts = ((.place_verdicts // {}) + $v)' "$s" > "$s.t" && mv "$s.t" "$s"
}
place_ok() {   # place_ok <project> <place>...: decided in the project itself (the message over the template's context)
  [[ -f "$1/docs/content/product-context.md" ]] || { mkdir -p "$1/docs/content"; cp "$PLACES_TPL/docs/content/product-context.md" "$1/docs/content/"; }
  python3 "$BATS_TEST_DIRNAME/../lib/aid-ui-place-ok.py" "$@" >/dev/null
}
