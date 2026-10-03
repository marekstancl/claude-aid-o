#!/usr/bin/env bash
# =============================================================================
# aid-ui-state.sh — the only writer of <project>/docs/design/brand-state.json
# and of the chapter statuses, bodies and font links in docs/brand/index.html (/aid-ui).
# The state lives outside the served docs/brand/; temp files go to <project>/.aid-ui/tmp/.
# Every PM decision comes from the studio page (lib/aid-ui-studio/server.py) through
# record-answer, and a mutation that needs the PM takes that answer once (P103 Step 4).
#
#   init <project>       creates brand-state.json; migrates an old docs/brand/state.json in
#                        this order: write the new file (template keys + old values), add
#                        missing sections/markers to index.html, move the old file to
#                        .aid-ui/state.json.migrated. New file present -> it wins. Markers
#                        are re-added on every init, so a retry repairs an interrupted run.
#   record-answer <project> --question <id>
#       asks the studio GET /answer?question=<id> with the session token
#       (<project>/.aid-ui/studio.token, header X-AID-Token) at $AID_UI_STUDIO_URL
#       (default http://$AID_UI_HOST:$AID_UI_STUDIO_PORT, 10.20.20.22:3915). The question
#       must be listed in .aid-ui/studio/payload.json and the answer be newer than its
#       opened_at, and its question, kind and target be those of the payload's question.
#       The URL must be http://127.0.0.1, http://localhost or http://$AID_UI_HOST (any port);
#       the token goes to curl on stdin, never on its command line. Stores .aid-ui/answers/<id>.json and answers.<id> = {kind, target,
#       decision, choice, comment, cards, cards_sha256, answer_file, answer_sha256, opened_at, at}
#       (cards = the question's cards as the studio showed them when the PM answered). Studio unreachable,
#       unanswered (404) or malformed -> exit 1, the question stays pending, nothing recorded.
#       A consumed answer is never re-recorded.
#   decide <project> --step <title|id> --title <text> --outcome <text> --why <text>
#          [--source <path|note>] [--reconstructed [--at <YYYY-MM-DDTHH:MM:SS[.mmm]Z>]]
#       records a decision the agent made without the PM: appends one line
#       {by: "agent", step: <the payload step's title>, event: {title, outcome, why, source?},
#       cards: [], answer: {decision: "decided", at}, reconstructed?: true} to
#       <project>/.aid-ui/studio/history.jsonl under flock -x (fd 8, 10 s; the studio server
#       takes the same lock) and prints `at`. Display record only: it never touches
#       brand-state.json, so a decided fact is still written by its own verb. --step must be a
#       steps[].title or steps[].id of .aid-ui/studio/payload.json (exact); title <= 80,
#       outcome <= 120, why <= 300 characters, none empty; --at only with --reconstructed (a
#       decision recorded after the fact). The same step, title and outcome already recorded
#       -> nothing appended, the recorded `at` printed, exit 0. Bad arguments -> exit 2;
#       no payload.json or the lock not taken -> exit 1.
#
#   Mutations that need the PM take --answer <question id>. The answer must be recorded,
#   of the verb's kind, for exactly the requested target, decided approve|choose, not in
#   `consumed`, its file unchanged, and the live studio must still give it (GET /answer as
#   record-answer does, same URL rule) with the same question, kind, target, decision and
#   cards_sha256;
#   studio unreachable or a mismatch -> exit 1. The mutation then consumes it. This
#   guards against an agent skipping or misapplying the PM's answer, not against one that
#   deliberately forges files and the server. Every verb but build-id holds an flock
#   on the docs/design directory (opened read-only, nothing is created or truncated)
#   across its read-check-write. Targets:
#     set variant|structure|content-plan <json>   kind variant|structure|content_plan,
#                          target sha256:<sha256 of `jq -S -c -j . <<<json`> (no newline)
#     set options <json>   kind variant, target sha256:<canonical options JSON> (as above)
#     set refs <json>      kind references, target sha256:<canonical refs JSON> (as above);
#                          <json> = the shown cards [{"id": <card id>, "url", "why"}]; the answer
#                          must be `choose` with its choice (one card id or a list) among the ids;
#                          card ids must be non-empty and unique, and the refs must be exactly
#                          the cards the studio showed for the answer's question when the PM
#                          answered (the live answer's `cards`, never payload.json) (same count; per id the card's url = url, its thesis = why; no
#                          other keys) (else exit 1, nothing written, answer not consumed);
#                          picked = id in the choice (set by this script, never by the caller)
#     chapter <project> <id> schvaleno            kind by chapter: vize vision, logo identity,
#                          seo seo_brief, struktura structure, obsah content_plan, produkt
#                          variant, smer direction, barvy typografie komponenty platformy
#                          ukazky kvalita schvaleni design_standard; target = what
#                          `chapter-target <project> <id>` prints: sha256:<sha256 of the
#                          chapter id, a newline, then the stored body, the bytes between
#                          <!-- body:<id> --> and <!-- /body:<id> -->> (the id binds the
#                          answer to this chapter). ceka and navrh need no answer.
#     chapter-all <project> [--by <who>]         kind handover, target = what `chapter-all-target
#                          <project>` prints: sha256:<sha256 of "<id>\n<chapter-target of id>\n" for
#                          every chapter in navrh or schvaleno, in CHAPTERS order> (a changed body
#                          of any of them changes it). One answer approves all of them.
#     approve-page <project> <page>               kind approve_page, target <page>@<fingerprint
#                          of the page in the recorded build>; refused when the site changed
#     defer-content <project> <item id>           kind defer_content, target <item id>;
#                          the content item's status -> deferred_by_pm
#     exception <project> --check <c> [--page|--viewport|--browser|--role|--state <v>]
#                          kind exception, target = the selector as JSON: an object with
#                          keys check page viewport browser role state, every value a string,
#                          omitted ones "*" (compared as JSON, key order free). One answer
#                          covers every matching row, bound to the fingerprints of the
#                          matching pages, _site and flows at that time; a changed
#                          fingerprint voids it for that page. Reason = the answer's comment.
#
#   set <project> product_type <json>
#   set <project> refs <json> --answer <id>      see Targets above
#   set <project> options <json> --answer <id>   keys vision seo images (true|false), identity
#                                        (false|"new"|"package"); only at step 0
#   step <project> <0-7>                 a backward step clears `finished`
#   roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>
#   chapter <project> <id> <ceka|navrh|schvaleno> [--by <who>]   schvaleno needs --answer <id>
#   chapter-target <project> <id>        prints the target of a `schvaleno` answer for chapter <id>
#   chapter-all <project> [--by <who>] --answer <id>   every chapter in navrh|schvaleno -> schvaleno
#   chapter-all-target <project>         prints the target of that one handover answer
#   reset-approvals <project> <id>...
#   body <project> <id> --file <html>    replaces only what is between <!-- body:<id> -->
#                                        and <!-- /body:<id> -->; refuses active or
#                                        structural content (script, on…=, section, markers);
#                                        a changed body of a `schvaleno` chapter resets it to `navrh`
#   fonts <project> <url-or-path>...     <link rel="stylesheet"> lines between <!-- fonts -->
#                                        markers; only https://fonts.googleapis.com/… or a
#                                        .css file under docs/brand/fonts/
#   brand-waive-target <project>         prints the target of a brand package waiver: the JSON
#                                        {"check":"brand_package","missing":[…]} of what
#                                        aid-ui-brand-package.py reports missing now (sorted);
#                                        refused when nothing is missing
#   brand-waive <project> --answer <id>  kind exception, target = brand-waive-target; stores
#                                        brand_package_waiver {missing, answer, reason, at}: the
#                                        check passes as WAIVED only while exactly these parts
#                                        are missing (another missing part voids it)
#   attest <project> <item id> --note <text>   attestations.<id> = {note, at}, only for a
#                                        coverage map item with an agent: disposition
#   build-record <project> <site dir>    writes nothing into the site: refused when the site holds
#                                        the project, lies in <project>/docs or <project>/.aid-ui,
#                                        or holds docs/design/brand-state.json or .aid-ui/. build id = sha256 over the lines
#                                        "<relative path> <sha256>" of every file, sorted;
#                                        a page = every .html but 404.html, key = its relative
#                                        path; page fingerprint = the same digest over the page
#                                        and the local non-.html files its href/src name;
#                                        _site = the digest over every file that is not a page.
#                                        -> build {id, dir, fingerprints, at} in the state and
#                                        <project>/.aid-ui/build.json
#   build-id <dir>                       prints the build id of <dir>
#   gate-record <project> <result.json>  refuses a result whose build_id or fingerprints are
#                                        not the recorded build's, that has a row status other
#                                        than pass|fail|warn|not_covered, or that misses a row of
#                                        the required matrix (below); stores gate {run_at,
#                                        result_file, result_sha256, build_id}; an exception
#                                        that matches no open row is marked resolved
#                                        (kept as history, never covers again)
#   finish <project>                     refuses unless: aid-ui-coverage.sh check exits 0 (3 only
#                                        with an approve|choose coverage_drift answer whose target
#                                        is the changed item ids, sorted, comma-joined); the site
#                                        recomputes to the recorded build and the gate is of that
#                                        build with its result file unchanged; the result has
#                                        every required row and only allowed statuses; every page
#                                        is approved at its current fingerprint; every open row
#                                        has a live exception; every consumed answer file is unchanged;
#                                        every content item is confirmed_client|deferred_by_pm
#
# Required matrix: every check of checks.yaml (next to the coverage map;
# AID_UI_COVERAGE_MAP points it at a fixture) x every combination: pages x viewports x
# browsers (role and state ""); for variant webapp|pwa also structure.flows[].id (as page)
# x its states x structure.roles (or "") x viewports x browsers. checks.yaml `applies.<check>`
# narrows one check: `browsers: [..]` and `viewports: [..]` keep only those, `flows: false` drops
# the flow rows, `scope: project` keeps one row (the home page index.html, else the first page,
# at the last viewport and the first browser left) for a check of the whole project;
# a combination a check does not apply to needs no row. Rows of page _site are extra. Open row = fail, not_covered, or warn on a check not in checks.yaml warn_only;
# only pass, or warn on a warn_only check, satisfies a row without an exception.
#
# Exit: 0 ok, 1 refused, 2 usage.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/../skills/ui-design/brand-page/state.template.json"
COVERAGE_MAP="${AID_UI_COVERAGE_MAP:-$HERE/../skills/ui-design/coverage/map.yaml}"
CHAPTERS=" produkt vize logo barvy typografie smer komponenty platformy ukazky seo struktura obsah kvalita schvaleni "

usage() { echo "ERROR: aid-ui-state.sh: ${1:-usage}; see the header of this script" >&2; exit 2; }
die() { echo "ERROR: aid-ui-state.sh: $1" >&2; exit 1; }
today() { date -u +%Y-%m-%d; }
now() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ; }

(( $# >= 2 )) || usage "need <verb> <project>"
VERB="$1"; PROJECT="$2"; shift 2
ANSWER=""; LIVE_ANSWER=""; rest=()   # --answer <id> may stand anywhere after <project>
while (( $# )); do
  if [[ "$1" == --answer ]]; then (( $# >= 2 )) || usage "--answer needs a question id"; ANSWER="$2"; shift 2
  else rest+=("$1"); shift; fi
done
set -- "${rest[@]+"${rest[@]}"}"
BRAND="$PROJECT/docs/brand"
HTML="$BRAND/index.html"
STATE="$PROJECT/docs/design/brand-state.json"
OLD="$BRAND/state.json"   # P101 location, migrated by init
if [[ "$VERB" != build-id ]]; then   # one mutation at a time: the answer check and the write are one step
  [[ "$VERB" != init ]] || mkdir -p "${STATE%/*}"
  if [[ -d "${STATE%/*}" ]]; then
    exec 9<"${STATE%/*}"   # read-only fd of the directory: a project symlink cannot make us write
    flock -w 60 9 || { echo "ERROR: aid-ui-state.sh: $STATE is locked by another aid-ui-state.sh for 60 s" >&2; exit 1; }
  fi
fi

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
            # a browser auto-closes li/dt/dd up through a div, popping the chapter's own wrapper
            parent = {"li": ("ul", "ol"), "dt": ("dl",), "dd": ("dl",)}.get(tag)
            if parent and (self.open_tags or [None])[-1] not in parent:
                self.refuse("<%s> outside a %s" % (tag, "list" if tag == "li" else "<dl>"))
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
    new = {"vize": ("Vize", "produkt"), "seo": ("SEO", "ukazky"),   # dict order = insertion order
           "struktura": ("Struktura", "seo"), "obsah": ("Obsah", "struktura"), "kvalita": ("Kvalita", "obsah")}
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

# Build ids, the required matrix and the finish conditions (see the header).
#   build <dir>                                   -> {id, fingerprints}   (id <dir> -> the id only)
#   exfp <state> <selector>                       -> fingerprints an exception binds to
#   gate <state> <checks.json> <result>           -> indices of exceptions now resolved
#   finish <state> <checks.json> <project> [<coverage_drift answer id>]
BUILD_PY="$(cat <<'PY'
import hashlib, json, os, re, sys
from urllib.parse import urlsplit, unquote
mode, args = sys.argv[1], sys.argv[2:]
AX = ("page", "viewport", "browser", "role", "state")
bad = []

def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        print("ERROR: aid-ui-state.sh: cannot read %s: %s" % (p, e), file=sys.stderr)
        sys.exit(1)

def sha_file(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def build(d):
    files = sorted(os.path.relpath(os.path.join(r, f), d) for r, _, fs in os.walk(d) for f in fs)
    sha = {f: sha_file(os.path.join(d, f)) for f in files}
    digest = lambda names: hashlib.sha256("".join("%s %s\n" % (n, sha[n]) for n in sorted(names)).encode()).hexdigest()
    pages = [f for f in files if f.endswith(".html") and os.path.basename(f) != "404.html"]
    fps = {}
    # ponytail: href/src attributes only; srcset and url() inside CSS are not followed (they count in _site)
    for p in pages:
        refs = {p}
        text = open(os.path.join(d, p), encoding="utf-8", errors="replace").read()
        for u in re.findall(r'''(?:href|src)\s*=\s*["']([^"']+)["']''', text, re.I):
            s = urlsplit(u)
            path = unquote(s.path)
            if s.scheme or s.netloc or not path:
                continue
            t = os.path.normpath(path.lstrip("/") if path.startswith("/") else os.path.join(os.path.dirname(p), path))
            if t in sha and not t.endswith(".html"):   # a link to another page is not part of this one
                refs.add(t)
        fps[p] = digest(refs)
    fps["_site"] = digest([f for f in files if f not in pages])
    return {"id": digest(files), "fingerprints": fps}

def val(x):
    return "" if x is None else str(x)

def fp_of(st, fps, page):   # a flow row has no file of its own: bound to the whole build
    return fps.get(page, "build:" + st["build"]["id"])

def combos(st, ck, fps, check=None):   # applies.<check>: browsers/viewports subset, flows false, scope project
    ap = (ck.get("applies") or {}).get(check) or {}
    vps, brs = [val(v) for v in ck.get("viewports") or []], [val(b) for b in ck.get("browsers") or []]
    if "browsers" in ap:
        brs = [b for b in brs if b in [val(x) for x in ap["browsers"] or []]]
    if "viewports" in ap:
        vps = [v for v in vps if v in [val(x) for x in ap["viewports"] or []]]
    pages = [p for p in sorted(fps) if p != "_site"]
    if ap.get("scope") == "project":
        home = "index.html" if "index.html" in pages else (pages[:1] or [""])[0]
        return [(home, vps[-1], brs[0], "", "")] if home and vps and brs else []
    out = [(p, v, b, "", "") for p in pages for v in vps for b in brs]
    if ((st.get("variant") or {}).get("type")) in ("webapp", "pwa") and ap.get("flows", True) is not False:
        s = st.get("structure") or {}
        roles = [val(r.get("id") if isinstance(r, dict) else r) for r in s.get("roles") or []] or [""]
        out += [(val(f.get("id")), v, b, r, val(x.get("id") if isinstance(x, dict) else x)) for f in s.get("flows") or [] for x in f.get("states") or []
                for r in roles for v in vps for b in brs]
    return out

def missing(st, ck, res, fps):
    have = {(val(r.get("check")),) + tuple(val(r.get(k)) for k in AX) for r in res.get("rows") or [] if isinstance(r, dict)}
    return ["%s %s" % (c, "/".join(x or "-" for x in k)) for c in ck.get("checks") or {} for k in combos(st, ck, fps, c)
            if (c,) + k not in have]

def matches(sel, row):
    return sel.get("check") == row.get("check") and all(sel.get(k) in ("*", val(row.get(k))) for k in AX)

STATUSES = ("pass", "fail", "warn", "not_covered")

def bad_rows(res):   # external gate output: a row of any other status is refused, never counted
    return ["row with status %s: %s" % (json.dumps(r.get("status") if isinstance(r, dict) else r),
            json.dumps(r, sort_keys=True)[:120]) for r in res.get("rows") or []
            if not isinstance(r, dict) or r.get("status") not in STATUSES]

def open_rows(ck, res):   # fail, not_covered, and warn on a check that is not warn_only
    wo = ck.get("warn_only") or []
    return [r for r in res.get("rows") or [] if isinstance(r, dict)
            and (r.get("status") in ("fail", "not_covered") or (r.get("status") == "warn" and r.get("check") not in wo))]

if mode in ("build", "id"):
    b = build(args[0])
    print(b["id"] if mode == "id" else json.dumps(b, sort_keys=True))
    sys.exit(0)

st = load(args[0])
if mode == "exfp":
    sel, fps = json.loads(args[1]), st["build"]["fingerprints"]
    keys = list(fps) + [val(f.get("id")) for f in (st.get("structure") or {}).get("flows") or []]
    print(json.dumps({k: fp_of(st, fps, k) for k in keys if sel["page"] in ("*", k)}, sort_keys=True))
elif mode == "gate":
    ck, res = load(args[1]), load(args[2])
    b = st["build"]
    if not isinstance(res, dict) or res.get("build_id") != b["id"]:
        bad.append("the result is for build %s, the recorded build is %s" % ((res or {}).get("build_id"), b["id"]))
    elif res.get("fingerprints") != b["fingerprints"]:
        bad.append("the result's page fingerprints are not the recorded build's")
    else:
        bad += bad_rows(res) + ["missing row: " + m for m in missing(st, ck, res, b["fingerprints"])]
    if not bad:
        rows = open_rows(ck, res)
        print(json.dumps([i for i, e in enumerate(st.get("exceptions") or [])
                          if not e.get("resolved") and not any(matches(e["selector"], r) for r in rows)]))
elif mode == "finish":
    ck, project = load(args[1]), args[2]
    drift = args[3] if len(args) > 3 else ""
    b, g = st.get("build"), st.get("gate")
    fps = {}
    if not b:
        bad.append("no build recorded; run build-record")
    elif not os.path.isdir(b.get("dir") or ""):
        bad.append("the recorded site directory %s is gone" % b.get("dir"))
    else:
        cur = build(b["dir"])
        fps = cur["fingerprints"]
        if cur["id"] != b["id"]:
            bad.append("the site in %s changed since build-record (build id %s, recorded %s); rebuild, build-record and run the gate again"
                       % (b["dir"], cur["id"][:12], b["id"][:12]))
    if not g:
        bad.append("no gate result recorded; run the gate (gate-record)")
    elif b:
        if g.get("build_id") != b["id"]:
            bad.append("the gate result is for build %s, not the recorded build %s" % (g.get("build_id", "")[:12], b["id"][:12]))
        rf = g.get("result_file") or ""
        if not os.path.isfile(rf) or sha_file(rf) != g.get("result_sha256"):
            bad.append("the gate result %s changed or is missing since gate-record" % rf)
        else:
            res = load(rf)
            if res.get("build_id") != b["id"] or res.get("fingerprints") != fps:
                bad.append("the gate result does not belong to the current build")
            bad += bad_rows(res) + ["missing row: " + m for m in missing(st, ck, res, fps)]
            live = [e for e in st.get("exceptions") or [] if not e.get("resolved")]
            for r in open_rows(ck, res):
                if not any(matches(e["selector"], r) and e.get("fingerprints", {}).get(val(r.get("page"))) == fp_of(st, fps, val(r.get("page")))
                           for e in live):
                    bad.append("%s row without a live exception: %s %s" % (r.get("status"), r.get("check"),
                               "/".join(val(r.get(k)) or "-" for k in AX)))
    appr = st.get("approvals") or {}
    for p in sorted(fps):
        if p != "_site" and (appr.get(p) or {}).get("fingerprint") != fps[p]:
            bad.append("page %s is not approved at its current fingerprint" % p)
    ans = st.get("answers") or {}
    for q in list(st.get("consumed") or []) + ([drift] if drift else []):
        a = ans.get(q) or {}
        f = os.path.join(project, a.get("answer_file") or "-")
        if not os.path.isfile(f) or sha_file(f) != a.get("answer_sha256"):
            bad.append("the answer file of %s changed or is missing since it was recorded" % q)
    for it in st.get("content_plan") or []:
        if it.get("status") not in ("confirmed_client", "deferred_by_pm"):
            bad.append("content item %s is %s (needs confirmed_client or deferred_by_pm)" % (it.get("id"), it.get("status")))
for m in bad:
    print("ERROR: aid-ui-state.sh: %s refused: %s" % ({"gate": "gate-record"}.get(mode, mode), m), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
)"

bpy() { python3 -c "$BUILD_PY" "$@"; }

checks_json() {   # checks.yaml next to the coverage map, as JSON in a temp file
  local f; f="$(tmpfile checks.json)"
  yq -o=json . "$(dirname "$COVERAGE_MAP")/checks.yaml" > "$f" || die "cannot read $(dirname "$COVERAGE_MAP")/checks.yaml"
  echo "$f"
}

# take_answer <kind> <target> — refuses unless --answer names a recorded, unused
# approve|choose answer of this kind for exactly this target (see the header).
take_answer() {
  local kind="$1" target="$2" why file sha
  [[ -n "$ANSWER" ]] || die "$VERB refused: needs --answer <question id>, the PM's answer on the studio page"
  why="$(jq -r --arg id "$ANSWER" --arg k "$kind" --arg t "$target" '
    .answers[$id] as $a
    | if $a == null then "no recorded answer \($id); run: aid-ui-state.sh record-answer --question \($id)"
      elif $a.kind != $k then "answer \($id) is a \($a.kind) answer, not \($k)"
      elif (if $k == "exception" then (try ($a.target | fromjson) catch null) != ($t | fromjson) else $a.target != $t end)
        then "answer \($id) is for \($a.target | tojson), not \($t)"
      elif ($a.decision | IN("approve", "choose") | not) then "answer \($id) decided \($a.decision), not approve or choose"
      elif any(.consumed[]?; . == $id) then "answer \($id) is already used"
      else "ok \($a.answer_sha256) \($a.answer_file)" end' "$STATE")"
  [[ "$why" == "ok "* ]] || die "$VERB refused: $why"
  why="${why#ok }"; sha="${why%% *}"; file="${why#* }"
  [[ -f "$PROJECT/$file" && "$(sha256sum "$PROJECT/$file" | cut -d' ' -f1)" == "$sha" ]] ||
    die "$VERB refused: the answer file $file changed or is missing since it was recorded"
  local body; body="$(tmpfile live-answer.json)"
  studio_fetch "$ANSWER" "$body" "$VERB refused: answer $ANSWER cannot be confirmed with the studio"
  [[ "$STUDIO_CODE" == 200 ]] || { rm -f "$body"; die "$VERB refused: the studio does not hold answer $ANSWER (HTTP $STUDIO_CODE); the recorded answer is not confirmed by the PM's page"; }
  jq -e --arg id "$ANSWER" --argjson s "$(jq -c --arg id "$ANSWER" '.answers[$id]' "$STATE")" \
    'type == "object" and .question == $id and .kind == $s.kind and .target == $s.target and .decision == $s.decision
     and (.cards | type) == "array" and (.cards_sha256 | type) == "string" and .cards_sha256 == $s.cards_sha256' \
    "$body" >/dev/null 2>&1 || { rm -f "$body"; die "$VERB refused: the studio's answer $ANSWER differs from the recorded one"; }
  LIVE_ANSWER="$(<"$body")"   # the studio's answer, with the cards it showed (set refs)
  rm -f "$body"
}

# studio_fetch <question id> <body file> <what happens on failure> — GET /answer from
# the studio with the token on curl's stdin; sets STUDIO_URL and STUDIO_CODE (HTTP status).
# No token, a URL outside the allowlist or an unreachable studio -> exit 1.
studio_fetch() {
  local qid="$1" body="$2" tokf="$PROJECT/.aid-ui/studio.token" host rc=0
  [[ -r "$tokf" ]] || { rm -f "$body"; die "no studio token $tokf; start the studio (aid-ui-serve.sh studio); $3"; }
  host="${AID_UI_HOST:-10.20.20.22}"
  STUDIO_URL="${AID_UI_STUDIO_URL:-http://$host:${AID_UI_STUDIO_PORT:-3915}}"
  [[ "$STUDIO_URL" =~ ^http://([^/:@]+)(:[0-9]+)?/?$ ]] &&
    [[ "${BASH_REMATCH[1]}" == 127.0.0.1 || "${BASH_REMATCH[1]}" == localhost || "${BASH_REMATCH[1]}" == "$host" ]] ||
    { rm -f "$body"; die "studio URL refused (only http://127.0.0.1, http://localhost or http://$host, any port): $STUDIO_URL"; }
  STUDIO_CODE="$(printf 'X-AID-Token: %s\n' "$(<"$tokf")" | curl -sS --max-time 10 -o "$body" -w '%{http_code}' -H @- \
    -- "${STUDIO_URL%/}/answer?question=$qid")" || rc=$?
  [[ "$rc" -eq 0 ]] || { rm -f "$body"; die "studio unreachable at $STUDIO_URL (curl exit $rc); $3"; }
}

# chapter_kind <id> — the studio question kind that approves chapter <id> (header, Targets)
chapter_kind() {
  case "$1" in
    vize) echo vision ;; logo) echo identity ;; seo) echo seo_brief ;; struktura) echo structure ;;
    obsah) echo content_plan ;; produkt) echo variant ;; smer) echo direction ;;
    *) echo design_standard ;;
  esac
}

# chapter_target <id> — sha256:<digest of "<id>\n" + the stored body of chapter <id> in index.html>
chapter_target() {
  [[ -f "$HTML" ]] || die "no $HTML"
  python3 - "$HTML" "$1" <<'PY' || die "no body markers for chapter $1 in $HTML"
import hashlib, sys
text = open(sys.argv[1], encoding="utf-8").read()
a, b = "<!-- body:%s -->" % sys.argv[2], "<!-- /body:%s -->" % sys.argv[2]
i, j = text.find(a), text.find(b)
if i < 0 or j < i: sys.exit(1)
print("sha256:" + hashlib.sha256((sys.argv[2] + "\n" + text[i + len(a):j]).encode("utf-8")).hexdigest(), end="")
PY
}

# ready_chapters — chapter ids in navrh or schvaleno, in CHAPTERS order (what one handover covers)
ready_chapters() {
  local id
  for id in $CHAPTERS; do
    case "$(jq -r --arg id "$id" '.chapters[$id].status // "ceka"' "$STATE")" in navrh|schvaleno) echo "$id" ;; esac
  done
  return 0
}

# chapter_all_target — sha256 over "<id>\n<chapter_target id>\n" of every ready chapter
chapter_all_target() {
  local id ids t
  ids="$(ready_chapters)"
  [[ -n "$ids" ]] || die "no chapter in navrh or schvaleno; nothing to hand over"
  { for id in $ids; do t="$(chapter_target "$id")" || exit 1; printf '%s\n%s\n' "$id" "$t"; done; } |
    sha256sum | { read -r h _; printf 'sha256:%s' "$h"; }
}

json_sha() { printf 'sha256:%s' "$(jq -S -c -j . <<<"$1" | sha256sum | cut -d' ' -f1)"; }

# build_current — the recorded build, refused when the site changed since build-record.
build_current() {
  local dir id
  read -r id dir < <(jq -r '"\(.build.id // "-") \(.build.dir // "")"' "$STATE")
  [[ -n "$dir" ]] || die "$VERB refused: no build recorded; run build-record"
  [[ -d "$dir" ]] || die "$VERB refused: the recorded site directory $dir is gone"
  [[ "$(bpy id "$dir")" == "$id" ]] || die "$VERB refused: the site in $dir changed since build-record; run build-record again"
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

  record-answer)
    need_state
    qid="$(opt question "$@")"
    [[ "$qid" =~ ^[A-Za-z0-9._-]+$ ]] || usage "record-answer needs --question <id> (letters, digits, . _ -)"
    jq -e --arg q "$qid" 'any(.consumed[]?; . == $q)' "$STATE" >/dev/null && die "answer $qid is already used; it is not recorded again"
    [[ -r "$PROJECT/.aid-ui/studio.token" ]] || die "no studio token $PROJECT/.aid-ui/studio.token; start the studio (aid-ui-serve.sh studio); $qid stays pending"
    pq="$(jq -c --arg q "$qid" 'first(.questions[]? | select(.id == $q and (.opened_at | type) == "string"))
      | {kind, target, opened_at}' "$PROJECT/.aid-ui/studio/payload.json" 2>/dev/null)" || pq=""
    [[ -n "$pq" ]] || die "question $qid is not listed in .aid-ui/studio/payload.json; nothing recorded"
    opened="$(jq -r .opened_at <<<"$pq")"
    body="$(tmpfile answer.json)"
    studio_fetch "$qid" "$body" "$qid stays pending, nothing recorded"
    [[ "$STUDIO_CODE" != 404 ]] || { rm -f "$body"; die "no answer to $qid yet; it stays pending: $STUDIO_URL"; }
    [[ "$STUDIO_CODE" == 200 ]] || { rm -f "$body"; die "the studio answered HTTP $STUDIO_CODE for $qid; nothing recorded"; }
    ans="$(jq -ec --arg q "$qid" 'select(type == "object" and .question == $q and (.kind | type) == "string"
      and has("target") and (.decision | type) == "string" and (.at | type) == "string"
      and (.cards | type) == "array" and (.cards_sha256 | type) == "string")' "$body" 2>/dev/null)" ||
      { rm -f "$body"; die "malformed answer from the studio for $qid; nothing recorded"; }
    jq -e --argjson p "$pq" '.kind == $p.kind and .target == $p.target' <<<"$ans" >/dev/null ||
      { rm -f "$body"; die "the studio's answer to $qid is for $(jq -c '[.kind, .target]' <<<"$ans"), not the listed question $(jq -c '[.kind, .target]' <<<"$pq"); nothing recorded"; }
    rm -f "$body"
    at="$(jq -r .at <<<"$ans")"
    [[ "$(date -u -d "$at" +%s%N 2>/dev/null || echo 0)" -gt "$(date -u -d "$opened" +%s%N 2>/dev/null || echo 0)" ]] ||
      die "the answer to $qid ($at) is not newer than its round ($opened); nothing recorded"
    file=".aid-ui/answers/$qid.json"
    mkdir -p "$PROJECT/.aid-ui/answers"
    printf '%s\n' "$ans" > "$PROJECT/$file"
    sha="$(sha256sum "$PROJECT/$file" | cut -d' ' -f1)"
    jq_write --arg q "$qid" --arg f "$file" --arg sha "$sha" --arg o "$opened" --argjson a "$ans" \
      '.answers[$q] = {kind: $a.kind, target: $a.target, decision: $a.decision, choice: $a.choice,
                       comment: $a.comment, cards: $a.cards, cards_sha256: $a.cards_sha256,
                       answer_file: $f, answer_sha256: $sha, opened_at: $o, at: $a.at}'
    echo "ANSWER $qid: $(jq -c '{kind, target, decision, choice}' <<<"$ans")"
    ;;

  set)
    need_state
    (( $# == 2 )) || usage "set needs <key> <json>"
    jq -e . >/dev/null 2>&1 <<<"$2" || usage "not JSON: $2"
    case "$1" in
      options)
        jq -e 'type == "object" and all(to_entries[]; if .key == "identity" then IN(.value; false, "new", "package")
               else IN(.key; "vision", "seo", "images") and (.value | type) == "boolean" end)' >/dev/null <<<"$2" \
          || usage "options: keys vision seo images (true|false) and identity (false|\"new\"|\"package\"): $2"
        st="$(jq -r .step "$STATE")"
        [[ "$st" == 0 ]] || die "set options refused at step $st: the options are chosen at step 0 and cannot change after"
        take_answer variant "$(json_sha "$2")"
        jq_write --argjson v "$2" --arg q "$ANSWER" '.options += $v | .consumed += [$q]'
        ;;
      refs)
        jq -e 'type == "array" and length > 0 and all(.[]; type == "object" and keys == ["id", "url", "why"]
               and (.id | type) == "string" and (.url | type) == "string" and (.why | type) == "string")' >/dev/null <<<"$2" \
          || usage "refs: the shown cards [{\"id\":…,\"url\":…,\"why\":…}], no other keys: $2"
        jq -e 'all(.[]; .id != "") and ([.[].id] | length == (unique | length))' >/dev/null <<<"$2" \
          || die "set refs refused: card ids must be non-empty and unique: $(jq -c '[.[].id]' <<<"$2")"
        take_answer references "$(json_sha "$2")"
        # the refs are exactly the cards the studio showed when the PM answered (its
        # in-memory snapshot, confirmed live by take_answer), never payload.json
        shown="$(jq -c '[.cards[] | {id, url, why: .thesis}] | sort_by(.id | tostring)' <<<"$LIVE_ANSWER" 2>/dev/null)" || shown=""
        jq -e --argjson s "${shown:-null}" 'sort_by(.id) == $s' >/dev/null <<<"$2" ||
          die "set refs refused: the refs are not the cards shown for question $ANSWER (id, url, thesis): shown $shown"
        picks="$(jq -c --arg q "$ANSWER" '.answers[$q] | if .decision == "choose" then [.choice | select(. != null)] | flatten else [] end' "$STATE")"
        jq -e --argjson c "$picks" 'length > 0 and ($c | length > 0) and ([.[].id] as $ids | all($c[]; IN($ids[])))' >/dev/null <<<"$2" ||
          die "set refs refused: answer $ANSWER chose $picks, not one or more of the shown cards $(jq -c '[.[].id]' <<<"$2")"
        jq_write --argjson v "$2" --argjson c "$picks" --arg q "$ANSWER" \
          '.refs = [$v[] | .picked = (.id | IN($c[]))] | .consumed += [$q]'
        ;;
      product_type) jq_write --argjson v "$2" '.product_type = $v' ;;
      variant|structure|content-plan)
        key="${1//-/_}"
        case "$key" in
          variant) shape='type == "object" and IN(.type; "web", "webapp", "pwa") and IN(.brand; "new", "existing", "none")
                          and (.local | type) == "boolean"' ;;
          structure) shape='type == "object" and (.pages | type) == "array" and all(.pages[]; (.id | type) == "string")
                          and ((.flows // []) | all(.[]; (.id | type) == "string" and (.states | type) == "array"))' ;;
          content_plan) shape='type == "array" and all(.[]; (.id | type) == "string"
                          and IN(.status; "missing", "draft", "confirmed_client", "deferred_by_pm"))' ;;
        esac
        jq -e "$shape" >/dev/null <<<"$2" || usage "set $1: not the $key shape of the Data Model: $2"
        take_answer "$key" "$(json_sha "$2")"
        jq_write --arg k "$key" --arg q "$ANSWER" --argjson v "$2" '.[$k] = $v | .consumed += [$q] | .finished = null'
        ;;
      *) usage "set cannot write '$1' (only: product_type refs options variant structure content-plan)" ;;
    esac
    ;;

  approve-page)
    need_state
    (( $# == 1 )) || usage "approve-page needs <page>"
    fp="$(jq -r --arg p "$1" 'if $p == "_site" then empty else .build.fingerprints[$p] // empty end' "$STATE")"
    [[ -n "$fp" ]] || die "approve-page refused: $1 is not a page of the recorded build"
    build_current
    take_answer approve_page "$1@$fp"
    jq_write --arg p "$1" --arg f "$fp" --arg q "$ANSWER" --arg at "$(now)" \
      '.approvals[$p] = {fingerprint: $f, answer: $q, at: $at} | .consumed += [$q]'
    echo "APPROVED: $1 at ${fp:0:12}"
    ;;

  defer-content)
    need_state
    (( $# == 1 )) || usage "defer-content needs <item id>"
    jq -e --arg i "$1" 'any(.content_plan[]?; .id == $i)' "$STATE" >/dev/null || die "defer-content refused: no content item $1"
    take_answer defer_content "$1"
    jq_write --arg i "$1" --arg q "$ANSWER" \
      '.content_plan |= map(if .id == $i then .status = "deferred_by_pm" | .answer = $q else . end) | .consumed += [$q]'
    ;;

  exception)
    need_state
    check="$(opt check "$@")"
    [[ -n "$check" && "$check" != "*" ]] || usage "exception needs --check <check name>"
    sel="$(jq -n -S -c --arg c "$check" --arg p "$(opt page "$@")" --arg v "$(opt viewport "$@")" --arg b "$(opt browser "$@")" \
      --arg r "$(opt role "$@")" --arg s "$(opt state "$@")" \
      '{check: $c, page: $p, viewport: $v, browser: $b, role: $r, state: $s} | map_values(if . == "" then "*" else . end)')"
    build_current
    take_answer exception "$sel"
    fps="$(bpy exfp "$STATE" "$sel")"
    jq_write --argjson s "$sel" --argjson f "$fps" --arg q "$ANSWER" --arg at "$(now)" \
      '.exceptions += [{selector: $s, fingerprints: $f, answer: $q, reason: (.answers[$q].comment // ""), at: $at}] | .consumed += [$q]'
    echo "EXCEPTION: $sel"
    ;;

  brand-waive-target|brand-waive)
    need_state
    bj="$(tmpfile brand-package.json)"
    python3 "$HERE/aid-ui-brand-package.py" "$PROJECT" --json "$bj" >/dev/null 2>&1 || true
    target="$(jq -S -c '{check: "brand_package", missing: (.missing | sort)}' "$bj" 2>/dev/null)" || target=""
    rm -f "$bj"
    [[ -n "$target" ]] || die "$VERB refused: aid-ui-brand-package.py gave no result for $PROJECT"
    [[ "$(jq '.missing | length' <<<"$target")" -gt 0 ]] || die "$VERB refused: nothing is missing in the brand package; no waiver needed"
    if [[ "$VERB" == brand-waive-target ]]; then echo "$target"; exit 0; fi
    take_answer exception "$target"
    jq_write --argjson t "$target" --arg q "$ANSWER" --arg at "$(now)" \
      '.brand_package_waiver = {missing: $t.missing, answer: $q, reason: (.answers[$q].comment // ""), at: $at} | .consumed += [$q]'
    echo "BRAND PACKAGE WAIVED: $(jq -r '.missing | join("; ")' <<<"$target")"
    ;;

  attest)
    need_state
    (( $# == 3 )) && [[ "$2" == --note && -n "$3" ]] || usage "attest needs <item id> --note <text>"
    yq -o=json '.items' "$COVERAGE_MAP" | jq -e --arg i "$1" 'any(.[]; .id == $i
      and ([.do | if type == "string" then . else .[] end] | any(startswith("agent:"))))' >/dev/null ||
      die "attest refused: $1 is not a coverage map item with an agent: disposition ($COVERAGE_MAP)"
    jq_write --arg i "$1" --arg n "$3" --arg at "$(now)" '.attestations[$i] = {note: $n, at: $at}'
    ;;

  build-id)
    [[ -d "$PROJECT" ]] || usage "build-id needs <dir>"
    bpy id "$PROJECT"
    ;;

  build-record)
    need_state
    (( $# == 1 )) && [[ -d "$1" ]] || usage "build-record needs <site dir>"
    site="$(realpath "$1")"; root="$(realpath "$PROJECT")"
    [[ "$root/" != "$site/"* && "$site/" != "$root/docs/"* && "$site/" != "$root/.aid-ui/"* \
       && ! -e "$site/docs/design/brand-state.json" && ! -e "$site/.aid-ui" ]] ||
      die "build-record refused: the site $site holds the project or its state (docs/, .aid-ui/); the state would land inside it"
    b="$(bpy build "$site")"
    rec="$(jq -c --arg d "$site" --arg at "$(now)" '{id, dir: $d, fingerprints, at: $at}' <<<"$b")"
    mkdir -p "$PROJECT/.aid-ui"
    tmp="$(tmpfile build.json)"; jq . <<<"$rec" > "$tmp" && mv "$tmp" "$PROJECT/.aid-ui/build.json"
    jq_write --argjson r "$rec" '.build = $r | .finished = null'
    echo "BUILD: $(jq -r .id <<<"$rec")"
    ;;

  gate-record)
    need_state
    (( $# == 1 )) && [[ -f "$1" ]] || usage "gate-record needs <result.json>"
    jq -e '.build.id' "$STATE" >/dev/null || die "gate-record refused: no build recorded; run build-record"
    res="$(realpath "$1")"
    ck="$(checks_json)"
    rc=0; resolve="$(bpy gate "$STATE" "$ck" "$res")" || rc=$?
    rm -f "$ck"
    [[ "$rc" -eq 0 ]] || exit 1
    jq_write --arg f "$res" --arg sha "$(sha256sum "$res" | cut -d' ' -f1)" --argjson r "$(jq -c '{run_at, build_id}' "$res")" \
      --argjson idx "$resolve" '.gate = {run_at: $r.run_at, result_file: $f, result_sha256: $sha, build_id: $r.build_id}
      | reduce $idx[] as $i (.; .exceptions[$i].resolved = $r.run_at) | .finished = null'
    echo "GATE: $(jq -r '[.rows[] | .status] | group_by(.) | map("\(.[0]) \(length)") | join(", ")' "$res")"
    ;;

  step)
    need_state
    [[ "${1:-}" =~ ^[0-7]$ ]] || usage "step needs 0-7"
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
    [[ "$CHAPTERS" == *" $1 "* ]] || usage "unknown chapter id: $1"
    if [[ "$2" == schvaleno ]]; then
      tgt="$(chapter_target "$1")" || exit 1
      take_answer "$(chapter_kind "$1")" "$tgt"
      write_chapter "$1" "$2" "$by"
      jq_write --arg id "$1" --arg q "$ANSWER" '.chapters[$id].answer = $q | .consumed += [$q]'
    else
      write_chapter "$1" "$2" "$by"
    fi
    ;;

  chapter-all)
    need_state
    (( $# == 0 || $# == 2 )) || usage "chapter-all takes [--by <who>]"
    by=""; (( $# == 2 )) && { [[ "$1" == --by ]] || usage "unknown option $1"; by="$2"; }
    tgt="$(chapter_all_target)" || exit 1
    take_answer handover "$tgt"
    # all or nothing: a failure part way restores index.html and the state as they were
    # (copied back into the same files, so their mode and inode stay; also on INT/TERM)
    bh="$(tmpfile index.html)"; bs="$(tmpfile brand-state.json)"; cp -p "$HTML" "$bh"; cp -p "$STATE" "$bs"
    restore() { cat "$bh" > "$HTML"; cat "$bs" > "$STATE"; rm -f "$bh" "$bs"; }
    trap 'restore; exit 1' INT TERM
    ids="$(ready_chapters | jq -R . | jq -sc .)"
    if ! ( for id in $(jq -r '.[]' <<<"$ids"); do write_chapter "$id" schvaleno "$by"; done
           jq_write --arg q "$ANSWER" --argjson ids "$ids" \
             'reduce $ids[] as $id (.; .chapters[$id].answer = $q) | .consumed += [$q]' ); then
      trap - INT TERM; restore; die "chapter-all refused: a chapter could not be written; nothing changed"
    fi
    trap - INT TERM; rm -f "$bh" "$bs"
    ;;

  chapter-all-target)
    need_state
    (( $# == 0 )) || usage "chapter-all-target takes no arguments"
    chapter_all_target; echo
    ;;

  chapter-target)
    (( $# == 1 )) || usage "chapter-target needs <id>"
    [[ "$CHAPTERS" == *" $1 "* ]] || usage "unknown chapter id: $1"
    chapter_target "$1"; echo
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
    before="$(cksum < "$HTML" 2>/dev/null || true)"
    html_edit body "$1" "$3"
    if [[ "$(cksum < "$HTML")" != "$before" && "$(jq -r --arg id "$1" '.chapters[$id].status' "$STATE")" == schvaleno ]]; then
      write_chapter "$1" navrh ""
      echo "body of $1 changed: approval cleared, status navrh"
    fi
    ;;

  fonts)
    need_state
    (( $# >= 1 )) || usage "fonts needs <url-or-path>..."
    html_edit fonts "$PROJECT" "$@"
    ;;


  finish)
    need_state
    rc=0; cov="$(bash "$HERE/aid-ui-coverage.sh" check "$PROJECT" 2>&1)" || rc=$?
    drift=""
    if [[ "$rc" -eq 3 ]]; then
      # lines "changed|moved: <old id> -> <new id>  (<text>)"; the target names the new ids
      ids="$(while IFS= read -r l; do [[ "$l" =~ ^(changed|moved):\  ]] || continue; l="${l#* -> }"; echo "${l%%  (*}"
             done <<<"$cov" | LC_ALL=C sort | paste -sd, -)"
      drift="$(jq -r --arg t "$ids" 'first(.answers | to_entries[] | select(.value.kind == "coverage_drift"
        and .value.target == $t and (.value.decision | IN("approve", "choose"))) | .key) // empty' "$STATE")"
      [[ -n "$drift" ]] || die "finish refused: the standards changed since the coverage map and no coverage_drift answer names exactly these items: $ids"
    elif [[ "$rc" -ne 0 ]]; then
      die "finish refused: aid-ui-coverage.sh check exited $rc: $cov"
    fi
    ck="$(checks_json)"
    rc=0; bpy finish "$STATE" "$ck" "$PROJECT" "$drift" || rc=$?
    rm -f "$ck"
    [[ "$rc" -eq 0 ]] || exit 1
    jq_write --arg d "$(today)" '.finished = $d'
    echo "FINISHED: $(today)"
    ;;

  decide)
    payload="$PROJECT/.aid-ui/studio/payload.json"
    step=""; title=""; outcome=""; why=""; source=""; at=""; recon=false
    while (( $# )); do   # own loop: --reconstructed is a flag, opt() reads only values
      case "$1" in
        --step|--title|--outcome|--why|--source|--at)
          (( $# >= 2 )) || usage "decide: $1 needs a value"; printf -v "${1#--}" '%s' "$2"; shift 2 ;;
        --reconstructed) recon=true; shift ;;
        *) usage "decide: unknown argument $1" ;;
      esac
    done
    [[ -n "$step" ]] || usage "decide needs --step <title|id>"
    for f in title:80 outcome:120 why:300; do
      n="${f%%:*}"; max="${f#*:}"; v="${!n}"
      [[ -n "${v//[[:space:]]/}" ]] || usage "decide needs a non-empty --$n"
      (( $(jq -rn --arg s "$v" '$s | length') <= max )) || usage "decide: --$n is over $max characters"
    done
    if [[ -n "$at" ]]; then
      $recon || usage "decide: --at only together with --reconstructed"
      [[ "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?Z$ ]] ||
        usage "decide: --at must be YYYY-MM-DDTHH:MM:SS[.mmm]Z (UTC)"
    fi
    [[ -f "$payload" ]] || die "decide: no studio payload in $PROJECT; the studio is not initialised"
    st="$(jq -r --arg s "$step" 'first(.steps[]? | select(.title == $s or .id == $s) | .title) // empty' "$payload")" ||
      die "decide: $payload is not readable JSON"
    [[ -n "$st" ]] || usage "decide: no step \"$step\" in $payload (steps: $(jq -r '[.steps[]?.title] | join(", ")' "$payload"))"
    hist="${payload%/*}/history.jsonl"
    exec 8>>"$hist"
    flock -x -w 10 8 || die "decide: $hist is locked by another writer for 10 s"
    prev="$(jq -rRn --arg s "$st" --arg t "$title" --arg o "$outcome" 'first(inputs | fromjson? | objects
      | select(.by == "agent" and .step == $s and .event.title == $t and .event.outcome == $o) | .answer.at) // empty' "$hist")"
    if [[ -n "$prev" ]]; then echo "$prev"; exit 0; fi
    [[ -n "$at" ]] || at="$(now)"
    jq -nc --arg s "$st" --arg t "$title" --arg o "$outcome" --arg w "$why" --arg src "$source" --arg at "$at" --argjson r "$recon" \
      '{by: "agent", step: $s, event: ({title: $t, outcome: $o, why: $w} + (if $src == "" then {} else {source: $src} end)),
        cards: [], answer: {decision: "decided", at: $at}} + (if $r then {reconstructed: true} else {} end)' >&8
    echo "$at"
    ;;

  *) usage "unknown verb: $VERB" ;;
esac
