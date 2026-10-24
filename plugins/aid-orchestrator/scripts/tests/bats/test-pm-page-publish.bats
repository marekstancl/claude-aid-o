#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-pm-page-publish.sh
# Where a page AID renders for the PM goes. Defects it catches: a page sent to a publisher the PM did not configure,
# a publisher command evaluated by a shell, a page counted as delivered that never reached the PM, the PM's link
# (which carries the key) written into a file.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  PUB="$AID_PLUGIN_PATH/scripts/aid-pm-page-publish.sh"
  R="$BATS_TEST_TMPDIR/My Proj"; mkdir -p "$R/.aid-o/config" "$R/.aid-o/work/evidence/P900" "$R/ui/public"
  git -C "$R" init -q
  printf 'project_name: "Lisa pro WAN"\n' > "$R/.aid-o/config/project.yaml"
  PAGE="$R/.aid-o/work/evidence/P900/plan-summary-artifact.html"
  printf '<style>p{color:red}</style><p>Plan P900 – "ok"</p>\n' > "$PAGE"
  FAKE="$BATS_TEST_TMPDIR/bin dir/fake publisher"; mkdir -p "${FAKE%/*}"
  cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG.argv"; cat > "$FAKE_LOG.stdin"
[[ -n "${FAKE_FAIL:-}" ]] && { echo "share is down" >&2; exit 3; }
echo "brand logo is shown" >&2
printf '%s\n' "${FAKE_OUT:-https://share.example/p/lisa-p900-plan#k=SECRETKEY}"
SH
  chmod +x "$FAKE"; export FAKE_LOG="$BATS_TEST_TMPDIR/fake"
  unset AID_PM_PAGE_PUBLISHER AID_PM_PAGE_PUBLISHER_SUBCOMMAND FAKE_FAIL FAKE_OUT
}

_pub() { run bash "$PUB" "$PAGE" --plan P900 --kind plan --title "P900 · plán" --project-root "$R"; }

@test "pm page: no publisher configured — artifact as before, nothing is called, no delivery record is owed" {
  _pub
  [ "$status" -eq 0 ]; [ "$output" = "artifact $PAGE" ]
  [ ! -e "$FAKE_LOG.argv" ] && [ ! -e "$PAGE.published.json" ]
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-pm-page.sh' && aid_pm_page_delivered '$PAGE'"
  [ "$status" -eq 0 ]
}

@test "pm page: a publisher gets the page byte for byte, the key, the title, the display name and the logo; the link goes to stdout, not into a file" {
  printf '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' > "$R/ui/public/favicon.svg"
  export AID_PM_PAGE_PUBLISHER="$FAKE" AID_PM_PAGE_PUBLISHER_SUBCOMMAND=publish-for-pm
  _pub
  echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"link https://share.example/p/lisa-p900-plan#k=SECRETKEY"* ]]
  [[ "$output" == *"publisher: brand logo is shown"* ]]           # stderr relayed, apart from the link line
  cmp "$PAGE" "$FAKE_LOG.stdin"
  [ "$(sed -n 1p "$FAKE_LOG.argv")" = publish-for-pm ]
  grep -qx -- "--key" "$FAKE_LOG.argv"; grep -qx "my-proj/P900/plan" "$FAKE_LOG.argv"
  grep -qx "P900 · plán" "$FAKE_LOG.argv"; grep -qx "Lisa pro WAN" "$FAKE_LOG.argv"
  grep -qx "$(realpath "$R/ui/public/favicon.svg")" "$FAKE_LOG.argv"
  # delivered: the record matches the page, and holds no link
  [ "$(jq -r .page_sha256 "$PAGE.published.json")" = "$(sha256sum "$PAGE" | cut -d' ' -f1)" ]
  ! grep -q SECRETKEY "$PAGE.published.json"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-pm-page.sh' && aid_pm_page_delivered '$PAGE'"
  [ "$status" -eq 0 ]
  # the page re-rendered after publishing: not delivered until published again
  echo '<p>changed</p>' >> "$PAGE"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-pm-page.sh' && aid_pm_page_delivered '$PAGE'"
  [ "$status" -eq 1 ]; [[ "$output" == *"changed after it was published"* ]]
}

@test "pm page: a refused page, no link or two lines is a failure — never 'artifact', no delivery record" {
  export AID_PM_PAGE_PUBLISHER="$FAKE"
  FAKE_FAIL=1 _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"refused the page (exit 3): share is down"* ]]; [[ "$output" != *artifact* ]]
  FAKE_OUT="not a link" _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"no https:// link"* ]]
  FAKE_OUT=$'https://a\nhttps://b' _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"not exactly one link"* ]]
  [ ! -e "$PAGE.published.json" ]
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-pm-page.sh' && AID_PM_PAGE_PUBLISHER='$FAKE' aid_pm_page_delivered '$PAGE'"
  [ "$status" -eq 1 ]; [[ "$output" == *"was not published to the PM"* ]]
}

@test "pm page: the publisher setting is a path, never a shell command; the subcommand is one word" {
  export AID_PM_PAGE_PUBLISHER="$FAKE; touch $BATS_TEST_TMPDIR/pwned"
  _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"not an executable file"* ]]; [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  export AID_PM_PAGE_PUBLISHER="$FAKE" AID_PM_PAGE_PUBLISHER_SUBCOMMAND='publish; rm -rf x'
  _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"must be one word"* ]]
}

@test "pm page: the logo — pm_page.logo outside the project, too big or not an SVG is an error; an unusable found one is skipped" {
  export AID_PM_PAGE_PUBLISHER="$FAKE"
  printf 'pm_page:\n  logo: ../outside.svg\n' >> "$R/.aid-o/config/project.yaml"; printf '<svg/>' > "$BATS_TEST_TMPDIR/outside.svg"
  _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"pm_page.logo"*"not a usable logo"* ]]
  printf 'project_name: x\n' > "$R/.aid-o/config/project.yaml"
  head -c 9000 /dev/zero | tr '\0' 'a' | sed 's/^/<svg>/' > "$R/ui/public/favicon.svg"
  _pub
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"ui/public/favicon.svg is not a usable logo"*"skipped"* ]]
  ! grep -qx -- "--logo" "$FAKE_LOG.argv"
}

@test "pm page: arguments — an unknown kind, a missing page, a bad plan id and a page over 2 MiB are refused before anything is sent" {
  export AID_PM_PAGE_PUBLISHER="$FAKE"
  run bash "$PUB" "$PAGE" --plan P900 --kind deck --title t --project-root "$R"; [ "$status" -eq 2 ]
  run bash "$PUB" "$R/none.html" --plan P900 --kind plan --title t --project-root "$R"; [ "$status" -eq 2 ]
  run bash "$PUB" "$PAGE" --plan 900 --kind plan --title t --project-root "$R"; [ "$status" -eq 2 ]
  head -c $((2 * 1024 * 1024 + 1)) /dev/zero | tr '\0' 'a' > "$PAGE"
  _pub
  [ "$status" -eq 1 ]; [[ "$output" == *"over the 2097152"* ]]
  [ ! -e "$FAKE_LOG.argv" ]
}
