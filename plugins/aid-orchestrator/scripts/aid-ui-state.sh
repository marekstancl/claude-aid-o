#!/usr/bin/env bash
# =============================================================================
# aid-ui-state.sh — the only writer of <project>/docs/design/brand-state.json
# and of the chapter statuses, bodies and font links in docs/brand/index.html (/aid-ui).
# The state lives outside the served docs/brand/; temp files go to <project>/.aid-ui/tmp/.
#
#   init <project>       creates brand-state.json; migrates an old docs/brand/state.json in
#                        this order: write the new file (template keys + old values), add
#                        missing sections/markers to index.html, move the old file to
#                        .aid-ui/state.json.migrated. New file present -> it wins. Markers
#                        are re-added on every init, so a retry repairs an interrupted run.
#   await-direction <project> --imp <impeccable CLI> --key <key> --page-url <url>
#       records direction_pending (key + page url) first, so steps 4-6 refuse while
#       the round is open, then runs `<imp> serve-question --wait --key <key>`
#       itself from <project> (repeats on exit 3). ANSWER {optionId != reroll} -> .aid-ui/
#       direction-answer.json + direction recorded + direction_pending cleared;
#       ANSWER reroll -> exit 3; page closed (exit 4) -> exit 1; anything
#       unparseable -> exit 1, no direction recorded. All but a valid answer
#       leave direction_pending set.
#       There is deliberately no verb that records a direction from a file the
#       caller supplies: the answer only ever comes from Impeccable's stdout.
#   await-choice <project> --kind <slogan|logo|pages> --screen <kind>-<n>.html --page-url <url>
#       a PM choice on a companion page, taken only from the page server's memory
#       (GET <url>/aid/confirmed?screen=<file>), never from .events or a file; <url>
#       must be http://localhost|127.0.0.1|[::1][:port]/ (else exit 2). Opens
#       choice_pending first (a re-run of the same round keeps its time); accepts
#       only a confirm newer than that record; records choices.<kind> + the answer
#       under .aid-ui/ with its hash. No confirm, older confirm, zero cards (slogan
#       without own text, logo), server unreachable or malformed -> exit 1, nothing
#       recorded. Every round is a new screen file; a recorded screen records once.
#       ponytail: asks the server once per call; the agent re-runs it after the PM confirms.
#   await-choice <project> --kind composition --imp <impeccable CLI> --key <key> --page-url <url>
#       any further Impeccable round (step 4): the await-direction code path,
#       recorded as choices.composition, open round in choice_pending.
#   pending-direction <project> --key <key> --page-url <url>
#   require-direction <project>
#   set <project> <product_type|refs|impeccable.surface_brief|impeccable.seed_key> <json>
#   set <project> options <json>         keys vision seo images (true|false), identity
#                                        (false|"new"|"package"); only at step 0
#   step <project> <0-6>                 direct jumps; refused by gates: any step while a
#                                        choice is open; 2-6 while an enabled option has
#                                        no choice (vision->slogan, identity "new"->logo,
#                                        seo->pages); 4-6 without a direction; 5-6 with
#                                        build path comp and no composition.
#                                        A backward step clears `finished`
#   roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>
#   chapter <project> <id> <ceka|navrh|schvaleno> [--by <who>]
#   reset-approvals <project> <id>...
#   body <project> <id> --file <html>    replaces only what is between <!-- body:<id> -->
#                                        and <!-- /body:<id> -->; refuses active or
#                                        structural content (script, on…=, section, markers)
#   fonts <project> <url-or-path>...     <link rel="stylesheet"> lines between <!-- fonts -->
#                                        markers; only https://fonts.googleapis.com/… or a
#                                        .css file under docs/brand/fonts/
#   finish <project>                     after step 6, with a direction and the step gates
#
# Exit: 0 ok, 1 refused, 2 usage. (await-direction, await-choice composition: 3 = re-roll requested.)
# =============================================================================
set -euo pipefail

TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/ui-design/brand-page" && pwd)/state.template.json"
CHAPTERS=" produkt vize logo barvy typografie smer komponenty platformy ukazky seo schvaleni "
SETTABLE=" product_type refs impeccable.surface_brief impeccable.seed_key "

usage() { echo "ERROR: aid-ui-state.sh: ${1:-usage}; see the header of this script" >&2; exit 2; }
die() { echo "ERROR: aid-ui-state.sh: $1" >&2; exit 1; }
today() { date -u +%Y-%m-%d; }
now() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ; }   # same shape as the companion server's `at`

(( $# >= 2 )) || usage "need <verb> <project>"
VERB="$1"; PROJECT="$2"; shift 2
BRAND="$PROJECT/docs/brand"
HTML="$BRAND/index.html"
STATE="$PROJECT/docs/design/brand-state.json"
OLD="$BRAND/state.json"   # P101 location, migrated by init

need_state() { [[ -f "$STATE" ]] || die "no $STATE; run: aid-ui-state.sh init $PROJECT"; }

tmpfile() { mkdir -p "$PROJECT/.aid-ui/tmp"; mktemp "$PROJECT/.aid-ui/tmp/$1.XXXXXX"; }

# Edits of index.html. Markers keep status, body and fonts disjoint regions.
HTML_PY="$(cat <<'PY'
import html, os, re, sys, urllib.parse
mode, path, args = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open(path, encoding="utf-8").read()

def fail(msg):
    print("ERROR: aid-ui-state.sh: " + msg, file=sys.stderr)
    sys.exit(1)

def between(text, cid, kind, new):   # replace what is between <!-- kind:cid --> markers
    a, b = "<!-- %s:%s -->" % (kind, cid), "<!-- /%s:%s -->" % (kind, cid)
    if text.count(a) > 1 or text.count(b) > 1:   # a smuggled copy would cut the region short
        fail("%s markers of section %s appear more than once in %s; fix the page by hand" % (kind, cid, path))
    out, n = re.subn(re.escape(a) + ".*?" + re.escape(b), lambda m: a + new + b, text, count=1, flags=re.S)
    if n != 1:
        fail("%s markers of section %s not found in %s; run: aid-ui-state.sh init" % (kind, cid, path))
    return out

if mode == "status":
    cid, status, date, by = args
    text, n = re.subn(r'(<section id="%s" data-status=")[^"]*"' % re.escape(cid),
                      lambda m: m.group(1) + status + '"', text, count=1)
    if n != 1:
        fail("section %s not found in %s" % (cid, path))
    text = between(text, cid, "status", " · ".join(html.escape(x) for x in (date, by) if x))
elif mode == "body":
    cid, src = args
    body = open(src, encoding="utf-8").read()
    # Allowlist, not denylist: only these tags and attributes, links only to safe schemes.
    from html.parser import HTMLParser
    TAGS = set("p br hr h2 h3 h4 ul ol li strong em b i a img figure figcaption table thead tbody "
               "tr th td blockquote code pre span div small dl dt dd".split())
    ATTRS = {"class": None, "alt": None, "title": None, "lang": None, "href": {"a"},
             "src": {"img"}, "width": {"img"}, "height": {"img"}, "loading": {"img"},
             "colspan": {"td", "th"}, "rowspan": {"td", "th"}}
    # style only as project tokens (swatches, type samples): prop: var(--name); ...
    decl = (r'(?:background|background-color|color|border-color|font-family|font-size|font-weight'
            r'|line-height|letter-spacing)\s*:\s*var\(--[a-z0-9-]+\)')
    STYLE = re.compile(r'%s(?:\s*;\s*%s)*\s*;?' % (decl, decl))
    def bad_url(v):   # the parser already decoded entities; the browser drops these chars
        v = re.sub(r'[\x00-\x20\x7f]+', '', v).lower()
        if v.startswith(("https://", "http://", "mailto:", "#", "/", "./", "../")):
            return False
        return ":" in v.split("/", 1)[0]   # relative path: no scheme before the first "/"
    VOID = {"br", "hr", "img"}
    class Check(HTMLParser):   # validates and re-serializes; the raw body never reaches the page
        out, open_tags = [], []   # open_tags: non-void tags still open, closed at the end
        def refuse(self, what):
            fail("body of section %s refused: %s contains %s" % (cid, src, what))
        def handle_starttag(self, tag, attrs):
            if tag not in TAGS:
                self.refuse("tag <%s>" % tag)
            for name, val in attrs:
                allowed = ATTRS.get(name, False)
                if name == "style" and STYLE.fullmatch((val or "").strip()):
                    continue
                if allowed is False or (allowed and tag not in allowed):
                    self.refuse("attribute %s on <%s>" % (name, tag))
                if name == "class" and re.search(r'(^|\s)status(\s|$)', val or ""):
                    self.refuse("class status")
                if name in ("href", "src") and bad_url(val or ""):
                    self.refuse("URL %r" % (val or "")[:40])
            self.out.append("<" + tag + "".join(' %s="%s"' % (n, html.escape(v or "", quote=True))
                                                for n, v in attrs) + ">")
            if tag not in VOID:
                self.open_tags.append(tag)
        def handle_startendtag(self, tag, attrs):   # <p/> is <p></p>
            self.handle_starttag(tag, attrs)
            if tag not in VOID:
                self.out.append("</%s>" % self.open_tags.pop())
        def handle_endtag(self, tag):
            if tag not in TAGS:
                self.refuse("tag </%s>" % tag)
            if tag in VOID:
                return
            if tag not in self.open_tags:   # a stray end tag would close the page's own wrappers
                self.refuse("an unbalanced end tag </%s>" % tag)
            while True:   # an end tag of a deeper open tag closes the ones above it first
                t = self.open_tags.pop()
                self.out.append("</%s>" % t)
                if t == tag:
                    break
        def handle_data(self, data):   # raw text; a browser would still open a tag here (<img\0...)
            if re.search(r'<[A-Za-z!/?]', data):
                self.refuse("an unparsable tag %r" % data[:40])
            self.out.append(html.escape(data, quote=False))
        def handle_entityref(self, name):
            self.out.append(html.escape(html.unescape("&%s;" % name), quote=False))
        def handle_charref(self, name):
            self.out.append(html.escape(html.unescape("&#%s;" % name), quote=False))
        def handle_comment(self, data):
            self.refuse("a comment")
        def handle_decl(self, decl):
            self.refuse("a declaration")
        def handle_pi(self, data):
            self.refuse("a processing instruction")
        def unknown_decl(self, data):
            self.refuse("a declaration")
    c = Check(convert_charrefs=False)
    if "<!--" in body or "-->" in body:   # also inside attribute values: a fake marker there cuts the next write short
        c.refuse("a comment marker")
    if re.search(r'</(?![A-Za-z][A-Za-z0-9]*\s*>)', body):   # browsers read attributes in end tags, html.parser does not
        c.refuse("an end tag with more than its name")
    # an invalid char reference (&#xZZ;) is text to a browser; html.parser would stall on it
    c.feed(re.sub(r'&#(?![0-9]|[xX][0-9a-fA-F])', '&amp;#', body))
    if re.search(r'<[A-Za-z!/?]', c.rawdata):   # close() would drop an unfinished tag silently
        c.refuse("an unfinished tag %r" % c.rawdata[:40])
    c.close()
    text = between(text, cid, "body", "".join(c.out + ["</%s>" % t for t in reversed(c.open_tags)]))
elif mode == "fonts":
    project = args[0]
    brand = os.path.realpath(os.path.join(project, "docs/brand"))
    fonts = os.path.join(brand, "fonts") + os.sep
    links = []
    for a in args[1:]:
        if "://" in a or a.startswith("//"):
            u = urllib.parse.urlsplit(a)
            if u.scheme != "https" or u.netloc != "fonts.googleapis.com":
                fail("font URL refused (only https://fonts.googleapis.com/...): " + a)
            href = a
        else:
            p = os.path.realpath(os.path.join(project, a))
            if not (p.startswith(fonts) and p.endswith(".css") and os.path.isfile(p)):
                fail("font path refused (only an existing .css under docs/brand/fonts/): " + a)
            href = os.path.relpath(p, brand)
        links.append('<link rel="stylesheet" href="%s">' % html.escape(href, quote=True))
    a, b = "<!-- fonts -->", "<!-- /fonts -->"
    text, n = re.subn(re.escape(a) + ".*?" + re.escape(b),
                      lambda m: a + "\n" + "".join(l + "\n" for l in links) + b, text, count=1, flags=re.S)
    if n != 1:
        fail("fonts markers not found in %s; run: aid-ui-state.sh init" % path)
elif mode == "upgrade":   # args: chapter ids in page order
    new = {"vize": ("Vize", "produkt"), "seo": ("SEO", "ukazky")}
    for cid, (title, prev) in new.items():
        if '<section id="%s"' % cid in text:
            continue
        m = re.search(r'<section id="%s".*?</section>\n?' % prev, text, re.S)
        if not m:
            fail("section %s not found in %s" % (prev, path))
        sec = '<section id="%s" data-status="ceka"><h2>%s</h2><p class="status"></p><div class="body"></div></section>\n' % (cid, title)
        text = text[:m.end()] + sec + text[m.end():]
        li = re.search(r'<li><a href="#%s">.*?</li>\n?' % prev, text)
        if li:
            text = text[:li.end()] + '<li><a href="#%s">%s</a></li>\n' % (cid, title) + text[li.end():]
    for cid in args:
        m = re.search(r'(<section id="%s"[^>]*>)(.*?)(</section>)' % cid, text, re.S)
        if not m:
            fail("section %s not found in %s" % (cid, path))
        inner = m.group(2)
        if "<!-- status:%s -->" % cid not in inner:
            inner = re.sub(r'(<p class="status">)(.*?)(</p>)', lambda x: "%s<!-- status:%s -->%s<!-- /status:%s -->%s"
                           % (x.group(1), cid, x.group(2), cid, x.group(3)), inner, count=1, flags=re.S)
        if "<!-- body:%s -->" % cid not in inner:   # greedy: an old body may hold nested divs
            inner = re.sub(r'(<div class="body">)(.*)(</div>\s*)$', lambda x: "%s<!-- body:%s -->%s<!-- /body:%s -->%s"
                           % (x.group(1), cid, x.group(2), cid, x.group(3)), inner, count=1, flags=re.S)
        if "<!-- status:%s -->" % cid not in inner or "<!-- body:%s -->" % cid not in inner:
            fail("section %s in %s has no status paragraph or body div" % (cid, path))
        text = text[:m.start(2)] + inner + text[m.end(2):]
    if "<!-- fonts -->" not in text:
        text = text.replace("</head>", "<!-- fonts -->\n<!-- /fonts -->\n</head>", 1)
sys.stdout.write(text)
PY
)"

# html_edit <mode> <args...> — atomic rewrite of index.html by $HTML_PY.
html_edit() {
  [[ -f "$HTML" ]] || die "no $HTML"
  local tmp; tmp="$(tmpfile index.html)"
  if python3 -c "$HTML_PY" "$1" "$HTML" "${@:2}" > "$tmp"; then mv "$tmp" "$HTML"; else rm -f "$tmp"; exit 1; fi
}

# jq_write <jq filter> [jq args...] — atomic rewrite of brand-state.json.
jq_write() {
  local tmp; tmp="$(tmpfile brand-state.json)"
  if jq "$@" "$STATE" > "$tmp"; then mv "$tmp" "$STATE"; else rm -f "$tmp"; die "could not write $STATE"; fi
}

opt() {   # opt <name> <args...> — value after --<name>
  local name="$1"; shift
  while (( $# )); do [[ "$1" == "--$name" ]] && { echo "${2:-}"; return; }; shift; done
}

require_direction() {   # prints what is missing, returns 1 when not recorded
  local opt_id file sha pend msg=""
  opt_id="$(jq -r '.direction.option_id // empty' "$STATE")"
  file="$(jq -r '.direction.answer_file // empty' "$STATE")"
  sha="$(jq -r '.direction.answer_sha256 // empty' "$STATE")"
  pend="$(jq -r 'if .direction_pending then "URL \(.direction_pending.page_url) key \(.direction_pending.key)" else empty end' "$STATE")"
  if [[ -z "$opt_id" ]]; then msg="no direction recorded (direction.option_id)"
  elif [[ ! -f "$PROJECT/$file" ]]; then msg="the answer file $file is missing"
  elif [[ "$(sha256sum "$PROJECT/$file" | cut -d' ' -f1)" != "$sha" ]]; then msg="the answer file $file changed since it was recorded"
  fi
  [[ -n "$pend" ]] && msg="${msg:+$msg; }a direction round is open and unanswered: $pend"
  [[ -z "$msg" ]] && return 0
  echo "ERROR: aid-ui-state.sh: $msg. The direction is chosen in step 3 by the PM on Impeccable's page." >&2
  return 1
}

# gates <n> <what> — refuses step n (or finish) while a choice is open, an enabled
# option has no choice, or the comp build path has no composition.
gates() {
  local msg
  msg="$(jq -r --argjson n "$1" '[
    (if .choice_pending then "a choice is open and unanswered: \(.choice_pending.kind) at \(.choice_pending.page_url)" else empty end),
    (if $n >= 2 and .options.vision == true and (.choices.slogan | not) then "vision is on and no slogan is chosen (step 1)" else empty end),
    (if $n >= 2 and .options.identity == "new" and (.choices.logo | not) then "identity is on and no logo is chosen (step 1)" else empty end),
    (if $n >= 2 and .options.seo == true and (.choices.pages | not) then "SEO is on and no page list is chosen (step 1)" else empty end),
    (if $n >= 5 and .direction.build_path == "comp" and (.choices.composition | not) then "the build path is comp and no composition is chosen (step 4)" else empty end)
    ] | join("; ")' "$STATE")"
  [[ -z "$msg" ]] && return 0
  echo "ERROR: aid-ui-state.sh: $2 refused: $msg" >&2
  return 1
}

# impeccable_round <direction|composition> <args...> — P101's gate: the answer only
# ever comes from `<imp> serve-question --wait` stdout, run by this script.
impeccable_round() {
  local kind="$1"; shift
  IMP="$(opt imp "$@")"; KEY="$(opt key "$@")"; URL="$(opt page-url "$@")"
  [[ -n "$IMP" && -n "$KEY" && -n "$URL" ]] || usage "await-$kind needs --imp --key --page-url"
  [[ "$IMP" == */* ]] && IMP="$(realpath -m "$IMP")"   # a relative CLI path survives the cd below
  [[ "$kind" == direction ]] || refuse_other_pending "$kind"
  if [[ "$kind" == direction ]]; then jq_write --arg k "$KEY" --arg u "$URL" '.direction_pending = {key: $k, page_url: $u}'
  else jq_write --arg k "$KEY" --arg u "$URL" --arg at "$(now)" '.choice_pending = {kind: "composition", key_or_screen: $k, page_url: $u, at: $at}'
  fi
  while :; do
    # Impeccable finds .impeccable/questions/<key> in its cwd: run it from the project.
    rc=0; out="$(cd "$PROJECT" && IMPECCABLE_QUESTION_FORCE=1 "$IMP" serve-question --wait --key "$KEY")" || rc=$?
    [[ "$rc" -eq 3 ]] || break
  done
  if [[ "$rc" -eq 4 ]]; then
    die "the page closed without the PM's answer; the round stays open: URL $URL key $KEY"
  fi
  [[ "$rc" -eq 0 ]] || die "serve-question --wait exited $rc; nothing recorded: $out"
  # Impeccable prints `ANSWER: {json}`; a bare JSON line is accepted too. Last one wins.
  answer="$(sed -n 's/^ANSWER: //; /^{.*}$/p' <<<"$out" | while IFS= read -r l; do
    jq -ec 'select(type == "object" and (.optionId | type) == "string")' <<<"$l" 2>/dev/null || true; done | tail -n1)"
  [[ -n "$answer" ]] || die "no ANSWER with an optionId in Impeccable's output; nothing recorded: $out"
  OPT="$(jq -r .optionId <<<"$answer")"
  if [[ "$OPT" == reroll ]]; then echo "REROLL: $answer"; exit 3; fi
  local file=".aid-ui/$kind-answer.json"
  mkdir -p "$PROJECT/.aid-ui"
  printf '%s\n' "$answer" > "$PROJECT/$file"
  SHA="$(sha256sum "$PROJECT/$file" | cut -d' ' -f1)"
  jq_write --arg kind "$kind" --arg o "$OPT" --arg k "$KEY" --arg f "$file" --arg sha "$SHA" --arg u "$URL" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg d "$(today)" '
    ({key: $k, answer_file: $f, answer_sha256: $sha, answered_at: $at, page_url: $u}) as $rec
    | if $kind == "direction"
      then .direction = ({option_id: $o} + $rec) | del(.direction_pending) | .decisions += [{step: 3, what: "direction \($o)", date: $d}]
      else .choices.composition = ({id: $o} + $rec) | .choice_pending = null | .decisions += [{step: 4, what: "composition \($o)", date: $d}]
      end'
  echo "${kind^^}: $OPT"
}

# refuse_other_pending <kind> — another kind's open round is never dropped;
# a new round of the same kind replaces the old one.
refuse_other_pending() {
  local pending
  pending="$(jq -r '.choice_pending | if . then "\(.kind) \(.key_or_screen)" else "" end' "$STATE")"
  [[ -z "$pending" || "${pending%% *}" == "$1" ]] ||
    die "a ${pending%% *} round is still open on ${pending#* }; answer it before a $1 round"
}

# companion_choice <slogan|logo|pages> <args...> — see await-choice in the header.
companion_choice() {
  local kind="$1"; shift
  local screen url since ans rc at n text file sha pending
  screen="$(opt screen "$@")"; url="$(opt page-url "$@")"
  [[ -n "$screen" && -n "$url" ]] || usage "await-choice --kind $kind needs --screen --page-url"
  [[ "$screen" =~ ^$kind-[0-9]+\.html$ ]] || usage "--screen must be a new $kind-<n>.html file per round: $screen"
  if [[ "$(jq -r --arg k "$kind" '.choices[$k].screen // empty' "$STATE")" == "$screen" ]]; then
    echo "CHOICE $kind: already recorded from $screen"; return 0
  fi
  # Only the companion server on this machine answers (not a page the agent could serve).
  [[ "$url" =~ ^http://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?(/.*)?$ ]] ||
    usage "--page-url must be http://localhost|127.0.0.1|[::1][:port]/ (the companion server on this machine): $url"
  refuse_other_pending "$kind"
  pending="$(jq -r '.choice_pending | if . then "\(.kind) \(.key_or_screen)" else "" end' "$STATE")"
  if [[ "$pending" != "$kind $screen" ]]; then
    jq_write --arg k "$kind" --arg s "$screen" --arg u "$url" --arg at "$(now)" \
      '.choice_pending = {kind: $k, key_or_screen: $s, page_url: $u, at: $at}'
  fi
  since="$(jq -r '.choice_pending.at' "$STATE")"
  rc=0; ans="$(curl -fsS --max-time 10 -- "${url%/}/aid/confirmed?screen=$screen")" || rc=$?
  [[ "$rc" -ne 22 ]] || die "no confirm on $screen yet; the round stays open: $url"
  [[ "$rc" -eq 0 ]] || die "companion server unreachable (curl exit $rc); the round stays open: $url"
  ans="$(jq -ec --arg s "$screen" 'select(type == "object" and .screen == $s and (.at | type) == "string"
    and (.selected | type) == "array" and all(.selected[]; type == "string") and ((.text // "") | type) == "string")' \
    <<<"$ans" 2>/dev/null)" || die "malformed answer from ${url%/}/aid/confirmed; nothing recorded"
  at="$(jq -r .at <<<"$ans")"
  [[ "$at" > "$since" ]] || die "the confirm on $screen ($at) predates this round ($since); the round stays open: $url"
  n="$(jq '.selected | length' <<<"$ans")"; text="$(jq -r '.text // ""' <<<"$ans")"
  if [[ "$n" -eq 0 && "$kind" != pages ]] && [[ "$kind" == logo || -z "$text" ]]; then
    die "the PM confirmed no $kind; the round stays open: $url"
  fi
  file=".aid-ui/choice-$kind.json"
  mkdir -p "$PROJECT/.aid-ui"
  printf '%s\n' "$ans" > "$PROJECT/$file"
  sha="$(sha256sum "$PROJECT/$file" | cut -d' ' -f1)"
  jq_write --arg kind "$kind" --arg f "$file" --arg sha "$sha" --arg u "$url" --arg s "$screen" \
    --arg at "$at" --arg d "$(today)" --argjson a "$ans" '
    .choices[$kind] = {id: ($a.selected | join(",")), screen: $s, answer_file: $f, answer_sha256: $sha, answered_at: $at, page_url: $u}
    | .choice_pending = null | .decisions += [{step: 1, what: "\($kind) \($a.selected | join(","))", date: $d}]'
  echo "CHOICE $kind: $(jq -c '{selected, text}' <<<"$ans")"
}

# write_chapter <id> <status> <by> — the section's data-status and status text, then the state.
write_chapter() {
  local id="$1" status="$2" by="$3" date=""
  [[ "$CHAPTERS" == *" $id "* ]] || usage "unknown chapter id: $id"
  case "$status" in ceka|navrh|schvaleno) ;; *) usage "unknown status: $status" ;; esac
  [[ "$status" == ceka ]] || date="$(today)"
  html_edit status "$id" "$status" "$date" "$by"
  jq_write --arg id "$id" --arg s "$status" --arg d "$date" --arg by "$by" \
    '.chapters[$id] = ({status: $s} + (if $d != "" then {date: $d} else {} end) + (if $by != "" then {by: $by} else {} end))'
}

case "$VERB" in
  init)
    mkdir -p "$BRAND" "${STATE%/*}"
    if [[ -f "$STATE" ]]; then echo "brand-state.json exists; continuing from step $(jq -r .step "$STATE")"
    else
      src="$TEMPLATE"; [[ -f "$OLD" ]] && src="$OLD"
      tmp="$(tmpfile brand-state.json)"
      jq -s '.[0] * .[1]' "$TEMPLATE" "$src" > "$tmp" || { rm -f "$tmp"; die "could not read $src"; }
      mv "$tmp" "$STATE"; echo "brand-state.json created: $STATE (from $src)"
    fi
    if [[ -f "$HTML" ]]; then html_edit upgrade $CHAPTERS; fi
    if [[ -f "$OLD" ]]; then
      mkdir -p "$PROJECT/.aid-ui"
      mv "$OLD" "$PROJECT/.aid-ui/state.json.migrated"   # out of the served folder
      echo "old $OLD moved to .aid-ui/state.json.migrated"
    fi
    ;;

  await-direction)
    need_state
    impeccable_round direction "$@"
    ;;

  await-choice)
    need_state
    KIND="$(opt kind "$@")"
    case "$KIND" in
      slogan|logo|pages) companion_choice "$KIND" "$@" ;;
      composition) impeccable_round composition "$@" ;;
      *) usage "await-choice needs --kind slogan|logo|pages|composition" ;;
    esac
    ;;

  pending-direction)
    need_state
    KEY="$(opt key "$@")"; URL="$(opt page-url "$@")"
    [[ -n "$KEY" && -n "$URL" ]] || usage "pending-direction needs --key --page-url"
    jq_write --arg k "$KEY" --arg u "$URL" '.direction_pending = {key: $k, page_url: $u}'
    ;;

  require-direction)
    need_state
    require_direction || exit 1
    echo "direction: $(jq -r .direction.option_id "$STATE")"
    ;;

  set)
    need_state
    (( $# == 2 )) || usage "set needs <key> <json>"
    [[ "$SETTABLE" == *" $1 "* || "$1" == options ]] || usage "set cannot write '$1' (only:$SETTABLE options)"
    jq -e . >/dev/null 2>&1 <<<"$2" || usage "not JSON: $2"
    if [[ "$1" == options ]]; then
      jq -e 'type == "object" and all(to_entries[]; if .key == "identity" then IN(.value; false, "new", "package")
             else IN(.key; "vision", "seo", "images") and (.value | type) == "boolean" end)' >/dev/null <<<"$2" \
        || usage "options: keys vision seo images (true|false) and identity (false|\"new\"|\"package\"): $2"
      st="$(jq -r .step "$STATE")"
      [[ "$st" == 0 ]] || die "set options refused at step $st: the options are chosen at step 0 and cannot change after"
      jq_write --argjson v "$2" '.options += $v'
    else
      jq_write --arg p "$1" --argjson v "$2" 'setpath($p | split("."); $v)'
    fi
    ;;

  step)
    need_state
    [[ "${1:-}" =~ ^[0-6]$ ]] || usage "step needs 0-6"
    gates "$1" "step $1" || exit 1
    if (( $1 >= 4 )) && ! require_direction; then die "step $1 refused: run step 3 first (/aid-ui 3)"; fi
    jq_write --argjson n "$1" 'if $n < .step then .finished = null else . end | .step = $n'
    ;;

  roles)
    need_state
    (( $# == 1 )) || usage "roles needs bg=..,ink=..,accent=..,display=..,body=.."
    tokens="$BRAND/tokens.css"; [[ -f "$tokens" ]] || die "no $tokens"
    declare -A R=()
    IFS=, read -ra pairs <<<"$1"
    for p in "${pairs[@]}"; do
      k="${p%%=*}"; v="${p#*=}"
      [[ " bg ink accent display body " == *" $k "* && "$v" =~ ^[a-z0-9-]+$ ]] || usage "bad role pair: $p"
      R[$k]="$v"
    done
    for k in bg ink accent display body; do [[ -n "${R[$k]:-}" ]] || usage "missing role: $k"; done
    for k in bg ink accent; do grep -q -- "--color-${R[$k]}:" "$tokens" || die "unknown color '${R[$k]}' for $k in $tokens"; done
    for k in display body; do grep -q -- "--font-${R[$k]}-family:" "$tokens" || die "unknown typography role '${R[$k]}' for $k in $tokens"; done
    tmp="$(tmpfile roles.css)"
    {
      echo "/* Written by aid-ui-state.sh roles; do not edit. */"
      echo ":root {"
      for k in bg ink accent; do echo "  --brand-$k: var(--color-${R[$k]});"; done
      # family is required above; the rest only when tokens.css defines it (base.css has fallbacks)
      for k in display body; do for f in family size weight line-height letter-spacing; do
        if grep -q -- "--font-${R[$k]}-$f:" "$tokens"; then echo "  --brand-$k-$f: var(--font-${R[$k]}-$f);"; fi; done; done
      echo "}"
    } > "$tmp"
    jq_write --arg bg "${R[bg]}" --arg ink "${R[ink]}" --arg ac "${R[accent]}" --arg d "${R[display]}" --arg b "${R[body]}" \
      '.roles = {bg: $bg, ink: $ink, accent: $ac, display: $d, body: $b}'
    mv "$tmp" "$BRAND/roles.css"
    ;;

  chapter)
    need_state
    (( $# == 2 || $# == 4 )) || usage "chapter needs <id> <status> [--by <who>]"
    by=""; (( $# == 4 )) && { [[ "$3" == --by ]] || usage "unknown option $3"; by="$4"; }
    write_chapter "$1" "$2" "$by"
    ;;

  reset-approvals)
    need_state
    (( $# >= 1 )) || usage "reset-approvals needs <id>..."
    for id in "$@"; do [[ "$CHAPTERS" == *" $id "* ]] || usage "unknown chapter id: $id"; done
    for id in "$@"; do
      if [[ "$(jq -r --arg id "$id" '.chapters[$id].status' "$STATE")" == schvaleno ]]; then write_chapter "$id" navrh ""; fi
    done
    ;;

  body)
    need_state
    (( $# == 3 )) && [[ "$2" == --file ]] || usage "body needs <id> --file <html>"
    [[ "$CHAPTERS" == *" $1 "* ]] || usage "unknown chapter id: $1"
    [[ -f "$3" ]] || die "no body file $3"
    html_edit body "$1" "$3"
    ;;

  fonts)
    need_state
    (( $# >= 1 )) || usage "fonts needs <url-or-path>..."
    html_edit fonts "$PROJECT" "$@"
    ;;

  finish)
    need_state
    st="$(jq -r .step "$STATE")"
    [[ "$st" == 6 ]] || die "finish refused: the project is at step $st; finish comes after step 6"
    require_direction || exit 1
    gates 6 finish || exit 1
    jq_write --arg d "$(today)" '.finished = $d'
    echo "FINISHED: $(today)"
    ;;

  *) usage "unknown verb: $VERB" ;;
esac
