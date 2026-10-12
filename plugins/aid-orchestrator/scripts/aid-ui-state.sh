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
#   changes <project>    open change questions (the PM pressed Změnit) the payload does not list yet, as
#                        JSON lines {question, cards}; exit 1 when there are none
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
#                          variant and options: when every card of the question carries `value` (the JSON
#                          that card stands for), the target is sha256:<canonical {card id: value}> and
#                          <json> must be the value of the card the PM chose
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
#                          variant, smer direction, podklady product_context, barvy typografie komponenty platformy
#                          ukazky kvalita schvaleni design_standard; target = what
#                          `chapter-target <project> <id>` prints: sha256:<sha256 of the
#                          chapter id, a newline, then the stored body, the bytes between
#                          <!-- body:<id> --> and <!-- /body:<id> -->> (the id binds the
#                          answer to this chapter). ceka and navrh need no answer.
#     chapter-all <project> [--by <who>]         kind handover, target = what `chapter-all-target
#                          <project>` prints: sha256:<sha256 of "<id>\n<chapter-target of id>\n" for
#                          every chapter in navrh or schvaleno, in CHAPTERS order> (a changed body
#                          of any of them changes it). One answer approves all of them.
#     context-check <project>                    exit 0 when the online research was put to the PM (a sources
#                          answer, approve or return, with target online@<project dir name>) and an answer of kind product_context,
#                          decision approve, targets docs/content/product-context.md@<sha256 of
#                          the file now> (step 1p); 1 naming why (no file, no approval, changed
#                          since approval). Steps 1v, 3 and 6 call it first.
#     exception-covered <project> <result.json>   (P108) prints one JSON line per open row of the
#                          result (fail, not_covered, warn outside warn_only of the checks.json next to
#                          it, as finish counts them) that a live PM exception covers (same selector and
#                          fingerprint test as finish), with the PM's reason; read by the customer page
#     copy-record <project> <run dir>            (P108) context-check, then aid-ui-copy.py record:
#                          the copy review of the run is verified and stored per page under
#                          copy_review.pages (see the header of aid-ui-copy.py for every refusal).
#     approve-page <project> <page>               kind approve_page, target <page>@<fingerprint
#                          of the page in the recorded build>; refused when the site changed
#     defer-content <project> <item id>           kind defer_content, target <item id>;
#                          the content item's status -> deferred_by_pm
#     confirm-content <project> [--item <id>]     (P108) the PM's approved copy verdict (kind
#                          copy_verdict, target copy@<sha256 of .aid-ui/copy/subject.json>) marks
#                          every draft|missing item sourced from docs/content/copy.json
#                          confirmed_client (approve only); with --item <id> --fact <key>, a facts
#                          answer about the registry as it is now (target docs/content/facts.yaml@<sha>)
#                          marks that one item, which must name the fact key in its id or need.
#                          confirmed_client is never written without an answer.
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
#   method <project> <kind>              the method before the output (PM 7. 10. 2026): prints every
#                                        method file of the question kind (sections.json methods;
#                                        "===== <path>" then its bytes - this is how the agent reads it)
#                                        and writes the receipt .aid-ui/method/<kind>.json
#                                        {kind, files: [{path, sha256}], at}; the studio refuses an open
#                                        question of a receipt kind without a receipt from the 12 hours
#                                        before it opened, or whose cards lack `method`. A kind with
#                                        null in the map: exit 1 naming the no_method question to ask
#                                        (target no_method@<kind>, cards adopt | pm | without); with a
#                                        recorded choose answer for it whose card value is pm or
#                                        without, writes {kind, files: [], waived: <answer id>, mode, at}
#                                        (mode pm: the studio then wants source podklady on every card)
#   payload-check <project>              validates .aid-ui/studio/payload.json as the studio does
#                                        (server.py --check): exit 1 and the reason; run after every write
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
#   links <project> --web <url> --customer <url>   (P108) the addresses the PM opens (both 200 after
#                                        redirects, no login) -> .aid-ui/links.json; the studio
#                                        refuses a handover question without them in its body
#   open-item <project> add --text <t> --owner <PM|klient|agent> [--due <date>] [--critical] [--evidence <t>]
#                          | critical <id> | done <id> [--evidence <t>]   (H7: a critical open item blocks
#                          publication: finish writes publish_blocked_by, the customer page says so; it ends only
#                          as done with --evidence, never by being un-marked)
#                                        (P108) what stays open after the run (customer page)
#   open-items-sync <project>            (P108) the PM's own items from the studio history (by pm)
#   chapter-all-target / chapter-all     (P108) refused before the final gate: the customer page must
#                                        be the one the recorded gate checked and the coverage report
#                                        not older than the gate result
#   finish <project>                     needs .aid-ui/links.json (both 200 again) and writes
#                                        .aid-ui/finish.json {finished, web, customer, verdict};
#                                        refuses unless: aid-ui-coverage.sh check exits 0 (3 only
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
CHAPTERS=" produkt podklady vize logo barvy typografie smer komponenty platformy ukazky seo struktura obsah kvalita schvaleni "

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
    new = {"podklady": ("Podklady", "produkt"), "vize": ("Vize", "podklady"), "seo": ("SEO", "ukazky"),   # dict order = insertion order
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
# The client's tab icon: once the brand package holds icons/favicon.svg, a copy sits next to the page
# (docs/brand/favicon.svg, served as is) and the head links it. Done on every rewrite, so a page made
# before the package gets it with the next chapter (PM 11. 10. 2026, 1A).
_brand = os.path.dirname(os.path.realpath(path))
_src = os.path.join(os.path.dirname(_brand), "design/brand-package/icons/favicon.svg")   # docs/design/...
_dst = os.path.join(_brand, "favicon.svg")
if os.path.isfile(_src):
    _b = open(_src, "rb").read()
    if not os.path.isfile(_dst) or open(_dst, "rb").read() != _b:
        open(_dst, "wb").write(_b)
if os.path.isfile(_dst) and 'rel="icon"' not in text:
    text = text.replace("</head>", '<link rel="icon" href="favicon.svg" type="image/svg+xml">\n</head>', 1)
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

# receipt_fresh <kind> [hours] — the method receipt .aid-ui/method/<kind>.json names every current
# file of the kind's method with its sha256 and is at most <hours> (12) old; else die with what to run.
receipt_fresh() {
  local kind="$1" hours="${2:-12}" r="$PROJECT/.aid-ui/method/$1.json" map="$HERE/../skills/ui-design/sections.json"
  [[ -f "$r" ]] || die "$VERB refused: no method receipt for $kind; run: aid-ui-state.sh method $PROJECT $kind (and read what it prints)"
  local at; at="$(jq -r '.at // empty' "$r")"
  [[ -n "$at" ]] || die "$VERB refused: receipt $r has no time"
  local age=$(( $(date -u +%s) - $(date -u -d "$at" +%s 2>/dev/null || echo 0) ))
  (( age >= 0 && age <= hours * 3600 )) || die "$VERB refused: the $kind receipt is $(( age / 3600 )) h old (limit $hours h); run aid-ui-state.sh method $PROJECT $kind again"
  local f path want have
  while IFS= read -r f; do
    path="$f"; [[ "$f" == /* ]] || path="$HERE/../$f"
    want="$(jq -r --arg f "$f" '.files[] | select(.path == $f) | .sha256' "$r")"
    have="$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)"
    [[ -n "$want" && "$want" == "$have" ]] || die "$VERB refused: the $kind receipt does not cover the current $f; run aid-ui-state.sh method $PROJECT $kind again"
  done < <(jq -r --arg k "$kind" '.methods[$k].files[]' "$map")
}

# url_ok <url> — the address answers 200 after redirects within 10 s, without a login (what the PM clicks)
url_ok() { [[ "$1" =~ ^https?:// ]] && [[ "$(curl -sS -o /dev/null -L --max-time 10 -w '%{http_code}' "$1" 2>/dev/null)" == 200 ]]; }

# links_json — .aid-ui/links.json (links <project> --web --customer) or die
links_json() {
  local f="$PROJECT/.aid-ui/links.json"
  [[ -f "$f" ]] && jq -e '(.web | type) == "string" and (.customer | type) == "string"' "$f" >/dev/null ||
    die "$VERB refused: no .aid-ui/links.json with web and customer; run: aid-ui-state.sh links $PROJECT --web <url> --customer <url>"
  echo "$f"
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
    # H4 (12. 10. 2026): an inline <style>/<script> block whose bytes appear on two or more pages is the shared
    # look, not the page: it leaves the page fingerprint (a shared CSS fix no longer voids every approval) and
    # gets its own fingerprint, `shared`, approved once as `_shared`
    texts = {p: open(os.path.join(d, p), encoding="utf-8", errors="replace").read() for p in pages}
    blk = re.compile(r"<(style|script)\b[^>]*>.*?</\1>", re.S | re.I)
    seen = {}
    for p, t in texts.items():
        for b in set(m.group(0) for m in blk.finditer(t)):
            seen.setdefault(b, set()).add(p)
    shared = sorted(b for b, ps in seen.items() if len(ps) >= 2)
    # ponytail: href/src attributes only; srcset and url() inside CSS are not followed (they count in _site)
    for p in pages:
        refs = {p}
        text = texts[p]
        own = text
        for b in shared:
            own = own.replace(b, "")
        sha[p] = hashlib.sha256(own.encode("utf-8", "surrogatepass")).hexdigest()
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
    out = {"id": hashlib.sha256("".join("%s %s\n" % (f, sha_file(os.path.join(d, f))) for f in files).encode()).hexdigest(), "fingerprints": fps}
    if shared:
        out["shared"] = hashlib.sha256("".join(shared).encode("utf-8", "surrogatepass")).hexdigest()
    return out

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

def reason_of(row):   # the check's reason without its numbers and specifics: text before the first ":" or "("
    d = val(row.get("detail")).strip().lower()
    return re.split(r"[:(]", d, 1)[0].strip()

def covers(st, fps, e, r):   # H4: a page-"*" exception holds while the row fails for the reason the PM excused
    if not matches(e["selector"], r):
        return False
    if e["selector"].get("page") == "*" and e.get("reasons"):
        return reason_of(r) in e["reasons"]
    return e.get("fingerprints", {}).get(val(r.get("page"))) == fp_of(st, fps, val(r.get("page")))

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
elif mode == "exreasons":   # the reasons of the gate's open rows this selector matches (page "*" exceptions)
    sel, res = json.loads(args[1]), (load(args[2]) if len(args) > 2 and os.path.isfile(args[2]) else {})
    print(json.dumps(sorted({reason_of(r) for r in res.get("rows") or [] if isinstance(r, dict)
                             and r.get("status") in ("fail", "warn", "not_covered") and matches(sel, r)}), ensure_ascii=False))
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
elif mode == "covered":   # open rows (as finish counts them) that a live PM exception covers
    res, fps = load(args[1]), (st.get("build") or {}).get("fingerprints") or {}
    ck = load(args[2]) if len(args) > 2 and os.path.isfile(args[2]) else {}
    live = [e for e in st.get("exceptions") or [] if not e.get("resolved")]
    for r in open_rows(ck, res):
        hit = next((e for e in live if covers(st, fps, e, r)), None)
        if hit:
            print(json.dumps({"row": {k: r.get(k) for k in ("check",) + AX}, "reason": hit.get("reason", ""), "answer": hit.get("answer")},
                             ensure_ascii=False, sort_keys=True))
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
                if not any(covers(st, fps, e, r) for e in live):
                    bad.append("%s row without a live exception: %s %s" % (r.get("status"), r.get("check"),
                               "/".join(val(r.get(k)) or "-" for k in AX)))
    appr = st.get("approvals") or {}
    for p in sorted(fps):
        if p != "_site" and (appr.get(p) or {}).get("fingerprint") != fps[p]:
            bad.append("page %s is not approved at its current fingerprint" % p)
    if b and b.get("shared") and (appr.get("_shared") or {}).get("fingerprint") != b["shared"]:
        bad.append("the shared look (_shared: inline style and script on every page) is not approved at its current fingerprint")
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
      elif (if $k == "exception" then ((try ($a.target | fromjson) catch null) | if type == "object" then with_entries(select(.value != "*")) else . end)
              != (($t | fromjson) | with_entries(select(.value != "*"))) else $a.target != $t end)
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
    -- "${STUDIO_URL%/}${4:-/answer?question=$qid}")" || rc=$?
  [[ "$rc" -eq 0 ]] || { rm -f "$body"; die "studio unreachable at $STUDIO_URL (curl exit $rc); $3"; }
}

# context_ok — docs/content/product-context.md exists and an approve answer of kind product_context
# targets its current sha256 (P108 step 1p); prints why not to stderr
context_ok() {
  local ctx="$PROJECT/docs/content/product-context.md" csha
  [[ -f "$ctx" ]] || { echo "context-check: no docs/content/product-context.md; run step 1p (Podklady)" >&2; return 1; }
  csha="$(sha256sum "$ctx" | cut -d' ' -f1)"
  if jq -e --arg t "docs/content/product-context.md@$csha" \
       '[.answers[]? | select(.kind == "product_context" and .decision == "approve" and .target == $t)] | length > 0' "$STATE" >/dev/null; then
  # the online research (customer-research Mode 2) was put to the PM as its own sources question,
  # answered yes or no - the skill never researches the public web about a firm unasked
  jq -e --arg t "online@$(basename "$(realpath "$PROJECT")")" '[.answers[]? | select(.kind == "sources" and .target == $t and (.decision == "approve" or .decision == "return"))] | length > 0' "$STATE" >/dev/null ||
    { echo "context-check: the PM was not asked about the online research: put a studio question of kind sources with target online@$(basename "$(realpath "$PROJECT")") (card: what would be searched and what taken), wait for approve or return, record-answer it; step 1p point 4. A project approved before 7. 10. 2026 asks it now, once." >&2; return 1; }
    echo "product context approved: $csha"
  elif jq -e '[.answers[]? | select(.kind == "product_context" and .decision == "approve")] | length > 0' "$STATE" >/dev/null; then
    echo "context-check: docs/content/product-context.md changed since the PM approved it; ask again (product_context)" >&2; return 1
  else
    echo "context-check: the PM has not approved docs/content/product-context.md (question product_context)" >&2; return 1
  fi
}

# chapter_kind <id> — the studio question kind that approves chapter <id> (header, Targets)
chapter_kind() {
  case "$1" in
    vize) echo vision ;; logo) echo identity ;; seo) echo seo_brief ;; struktura) echo structure ;;
    obsah) echo content_plan ;; produkt) echo variant ;; smer) echo direction ;; podklady) echo product_context ;;
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
# end_in_order — the handover comes after the final gate: the customer page is the one the recorded gate
# checked (aid-ui-customer-page.py --check = 0) and the coverage report is not older than the gate result
# (P108: on 9. 10. the PM handed over twice because the last gate changed the numbers after his answer).
end_in_order() {
  jq -e '.gate.result_file' "$STATE" >/dev/null || die "$VERB refused: no gate recorded; the handover comes after the final gate (step 7)"
  local res; res="$(jq -r '.gate.result_file' "$STATE")"
  [[ -f "$res" ]] || die "$VERB refused: the recorded gate result $res is gone"
  jq -e '[.rows[] | select(.check == "customer_page")] | length > 0 and all(.[]; .status == "pass")' "$res" >/dev/null ||
    die "$VERB refused: the recorded gate did not pass the customer page (row customer_page); make the page, run the gate, gate-record, then the handover"
  local page="$PROJECT/docs/zakaznik/index.html"
  [[ -f "$page" && "$(sha256sum "$page" | cut -d' ' -f1)" == "$(jq -r '.gate.customer_page_sha256 // ""' "$STATE")" ]] ||
    die "$VERB refused: docs/zakaznik/index.html is missing or not the page the recorded gate ran over (sha); the gate must run over the page the PM gets, then gate-record, then the handover"
  local summ="$PROJECT/docs/design/soulad-summary.json"
  [[ -f "$summ" && "$(jq -r '.gate_run_at // ""' "$summ")" == "$(jq -r '.gate.run_at' "$STATE")" ]] ||
    die "$VERB refused: docs/design/soulad-summary.json is not from the recorded gate (gate_run_at); run aid-ui-coverage.sh report after the final gate, then the chapters, then the handover"
}

chapter_all_target() {
  local id ids t
  ids="$(ready_chapters)"
  [[ -n "$ids" ]] || die "no chapter in navrh or schvaleno; nothing to hand over"
  end_in_order
  { for id in $ids; do t="$(chapter_target "$id")" || exit 1; printf '%s\n%s\n' "$id" "$t"; done; } |
    sha256sum | { read -r h _; printf 'sha256:%s' "$h"; }
}

json_sha() { printf 'sha256:%s' "$(jq -S -c -j . <<<"$1" | sha256sum | cut -d' ' -f1)"; }

# choice_target <json> — the target the answer must carry for this JSON. One proposal: the sha256 of
# the JSON. Cards that each carry `value` (the JSON that card stands for): the sha256 of the map
# {card id: value} of the cards the studio showed, and the JSON must be the value of the card the PM
# chose - so the PM can pick any of the offered cards, not only the recommended one.
choice_target() {
  local m
  # no card carries a value -> one proposal (legacy); any card carries one -> all must, or the verb is refused
  m="$(jq -c --arg id "${ANSWER:-}" --argjson v "$1" '.answers[$id] as $a | ($a.cards // []) as $c
       | if ($a == null) or (any($c[]; type == "object" and .value != null) | not) then "legacy"
         elif all($c[]; type == "object" and (.value | type) == "object" and (.id | type) == "string" and .id != "") | not
           then "bad: every card needs a string id and an object value"
         elif ([$c[].id] | length != (unique | length)) then "bad: card ids repeat"
         elif $a.decision != "choose" or ($a.choice | type) != "string" then "bad: the answer is not a choice of one card"
         elif any($c[]; .id == $a.choice and .value == $v) | not then "bad: the PM chose card \($a.choice), and its value is not this JSON"
         else ($c | map({key: .id, value}) | from_entries) end' "$STATE")" \
    || die "$VERB refused: the recorded answer ${ANSWER:-} cannot be read"
  case "$m" in
    '"legacy"') json_sha "$1" ;;
    '"bad: '*) m="${m#\"bad: }"; die "$VERB refused: answer $ANSWER: ${m%\"}" ;;
    '{'*) json_sha "$m" ;;
    *) die "$VERB refused: the recorded answer ${ANSWER:-} cannot be read" ;;
  esac
}

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

  changes)
    # the PM pressed "Změnit": print each open change question the payload does not list yet (with its cards)
    # as one JSON line and exit 0; none -> exit 1. The agent adds it to the payload, waits for its answer
    # and applies the step's mutation again with --answer <new id>.
    need_state
    body="$(tmpfile state.json)"
    studio_fetch "" "$body" "no changes read" "/state"
    [[ "$STUDIO_CODE" == 200 ]] || { rm -f "$body"; die "the studio answered HTTP $STUDIO_CODE for /state"; }
    listed="$(jq -c '[.questions[]?.id]' "$PROJECT/.aid-ui/studio/payload.json" 2>/dev/null || echo '[]')"
    out="$(jq -c --argjson l "$listed" '. as $s | .questions[]? | select(.changed_from and (.answered | not) and ((.id) as $i | $l | index($i) | not))
      | . as $q | {question: (del(.answered, .answer, .changed_to)), cards: [$s.cards[]? | select(.question == $q.id)]}' "$body" 2>/dev/null)"
    rm -f "$body"
    [[ -n "$out" ]] || exit 1
    printf '%s\n' "$out"
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
        tgt="$(choice_target "$2")" || exit 1
        take_answer variant "$tgt"
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
        if [[ "$key" == variant ]]; then tgt="$(choice_target "$2")" || exit 1; else tgt="$(json_sha "$2")"; fi
        take_answer "$key" "$tgt"
        # a content item the studio writes (owner agent, not deferred) gets its text source when the plan names none:
        # confirm-content confirms texts by that source (Coufal 11. 10. 2026: a plan without sources confirmed 0 items)
        v="$2"
        [[ "$key" == content_plan ]] && v="$(jq -c '[.[] | if (.owner == "agent" and .status != "deferred_by_pm" and ((.source // "") == "")) then . + {source: "docs/content/copy.json"} else . end]' <<<"$2")"
        jq_write --arg k "$key" --arg q "$ANSWER" --argjson v "$v" '.[$k] = $v | .consumed += [$q] | .finished = null'
        ;;
      *) usage "set cannot write '$1' (only: product_type refs options variant structure content-plan)" ;;
    esac
    ;;

  approve-page)
    need_state
    (( $# == 1 )) || usage "approve-page needs <page>"
    fp="$(jq -r --arg p "$1" 'if $p == "_site" then empty elif $p == "_shared" then .build.shared // empty else .build.fingerprints[$p] // empty end' "$STATE")"
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

  confirm-content)
    need_state
    item="$(opt item "$@")"; fact="$(opt fact "$@")"
    if [[ -n "$item" || -n "$fact" ]]; then
      [[ -n "$item" && -n "$fact" ]] || usage "confirm-content needs --item <id> --fact <key> together"
      jq -e --arg i "$item" 'any(.content_plan[]?; .id == $i)' "$STATE" >/dev/null || die "confirm-content refused: no content item $item"
      fy="$PROJECT/docs/content/facts.yaml"
      [[ -f "$fy" ]] || die "confirm-content refused: no $fy"
      yq -e --arg k "$fact" '.[$k] != null' "$fy" >/dev/null 2>&1 || yq -e ".\"$fact\" != null" "$fy" >/dev/null 2>&1 ||
        die "confirm-content refused: no fact $fact in docs/content/facts.yaml"
      # the item must name the fact: its id or its need, compared without case and diacritics
      jq -e --arg i "$item" --arg k "$fact" '
        def norm: ascii_downcase | gsub("č";"c") | gsub("ě";"e") | gsub("š";"s") | gsub("ř";"r") | gsub("ž";"z") | gsub("ý";"y") | gsub("á";"a") | gsub("í";"i") | gsub("é";"e") | gsub("ú";"u") | gsub("ů";"u") | gsub("ň";"n") | gsub("ť";"t") | gsub("ď";"d") | gsub("ô";"o") | gsub("ľ";"l") | gsub("ä";"a");
        any(.content_plan[]; .id == $i and ((.id | norm) + " " + ((.need // "") | norm) | contains($k | norm)))' "$STATE" >/dev/null ||
        die "confirm-content refused: item $item does not name the fact $fact (in its id or need)"
      # the facts answer is about the registry as it is now (the question's target)
      take_answer facts "docs/content/facts.yaml@$(sha256sum "$fy" | cut -d' ' -f1)"
      jq_write --arg i "$item" --arg q "$ANSWER" --arg k "$fact" \
        '.content_plan |= map(if .id == $i then .status = "confirmed_client" | .answer = $q | .fact = $k else . end) | .consumed += [$q]'
      echo "CONFIRMED: $item (fact $fact)"
    else
      [[ -n "$ANSWER" ]] || die "confirm-content refused: needs --answer <question id>, the PM's copy verdict on the studio page"
      sub="$PROJECT/.aid-ui/copy/subject.json"
      [[ -f "$sub" ]] || die "confirm-content refused: no $sub (aid-ui-verify.sh --copy-subject)"
      [[ "$(jq -r --arg q "$ANSWER" '.answers[$q].decision // ""' "$STATE")" == approve ]] ||
        die "confirm-content refused: the copy verdict $ANSWER is not an approve (texts accepted as they are)"
      take_answer copy_verdict "copy@$(sha256sum "$sub" | cut -d' ' -f1)"
      # a text item names docs/content/copy.json as its source (step 3 writes it); a plan without any such item
      # cannot be confirmed as a whole, and the verdict is NOT consumed for nothing (Coufal 11. 10. 2026: 0 of 35)
      n="$(jq '[.content_plan[]? | select(.source == "docs/content/copy.json" and IN(.status; "draft", "missing"))] | length' "$STATE")"
      (( n > 0 )) || die "confirm-content refused: no draft or missing item with source docs/content/copy.json (step 3 sets it on every text the studio writes); nothing consumed"
      jq_write --arg q "$ANSWER" '.content_plan |= map(if .source == "docs/content/copy.json" and IN(.status; "draft", "missing")
        then .status = "confirmed_client" | .answer = $q else . end) | .consumed += [$q]'
      echo "CONFIRMED: $n text items"
    fi
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
    reasons='[]'
    if [[ "$(jq -r .page <<<"$sel")" == "*" ]]; then
      reasons="$(bpy exreasons "$STATE" "$sel" "$PROJECT/.aid-ui/verify/result.json")"
      [[ "$reasons" != "[]" ]] || die "exception refused: a page-* exception is bound to the reason the gate gives; the recorded result has no open $check row (run the gate first)"
    fi
    jq_write --argjson s "$sel" --argjson f "$fps" --argjson r "$reasons" --arg q "$ANSWER" --arg at "$(now)" \
      '.exceptions += [{selector: $s, fingerprints: $f, answer: $q, reason: (.answers[$q].comment // ""), at: $at}
        + (if ($r | length) > 0 then {reasons: $r} else {} end)] | .consumed += [$q]'
    echo "EXCEPTION: $sel${reasons:+ reasons $reasons}"
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
    # the method before the output (P108, 10. 10. 2026): the build was made after reading the build method
    receipt_fresh build
    # the reference's motion, as the PM saw it with the directions, runs in the build (P108)
    motion_note=""
    if jq -e 'any(.refs[]?; .picked == true)' "$STATE" >/dev/null; then
      inv="$PROJECT/.aid-ui/motion.json"
      [[ -f "$inv" ]] || die "build-record refused: a reference is picked but there is no .aid-ui/motion.json (aid-ui-motion.py inventory, step 5)"
      msha="$(sha256sum "$inv" | cut -d' ' -f1)"
      jq -e --arg t "smer:$msha" 'any(.answers[]?; .kind == "direction" and .decision == "choose" and .target == $t)' "$STATE" >/dev/null ||
        die "build-record refused: no recorded direction choice for the inventory as it is now (target smer:$msha); the PM chose a direction over another inventory, or the inventory changed since"
      obs="$PROJECT/.aid-ui/build.motion.json"
      [[ -f "$obs" ]] || die "build-record refused: no .aid-ui/build.motion.json: observe the built site first - aid-ui-tool.sh motion <url of the served site> $obs --dir-sha256 \"\$(aid-ui-motion.py dirsha $site)\""
      motion_note="$(python3 "$HERE/aid-ui-motion.py" check "$PROJECT" --observed "$obs" --dir "$site" --write "$PROJECT/.aid-ui/build.motion.check.json" 2>&1)" ||
        die "build-record refused: the build does not carry the reference's motion: $motion_note"
    fi
    b="$(bpy build "$site")"
    rec="$(jq -c --arg d "$site" --arg at "$(now)" '{id, dir: $d, fingerprints, at: $at} + (if .shared then {shared} else {} end)' <<<"$b")"
    mkdir -p "$PROJECT/.aid-ui"
    tmp="$(tmpfile build.json)"; jq . <<<"$rec" > "$tmp" && mv "$tmp" "$PROJECT/.aid-ui/build.json"
    # H4: say which approvals the new build voids and why (a page's own content, or the shared look)
    lost="$(jq -r --argjson r "$rec" '(.approvals // {}) as $a | [($a | to_entries[] | select(.key != "_shared")
      | select(($r.fingerprints[.key] // "") != .value.fingerprint) | .key)] + (if ($a._shared and ($a._shared.fingerprint != ($r.shared // ""))) then ["_shared (společný styl)"] else [] end) | join(", ")' "$STATE")"
    jq_write --argjson r "$rec" '.build = $r | .finished = null'
    [[ -z "$lost" ]] || echo "APPROVALS VOID (their page changed): $lost"
    rm -f "$PROJECT/.aid-ui/finish.json" "$PROJECT/.aid-ui/links.json"   # a new build: the end starts over
    echo "BUILD: $(jq -r .id <<<"$rec")${motion_note:+ · ${motion_note%%$'\n'*}}"
    ;;

  gate-record)
    need_state
    (( $# == 1 )) && [[ -f "$1" ]] || usage "gate-record needs <result.json>"
    jq -e '.build.id' "$STATE" >/dev/null || die "gate-record refused: no build recorded; run build-record"
    res="$(realpath "$1")"
    # the same run recorded twice = the gate did not run (9. 10.: --copy-subject mistaken for a gate run)
    [[ "$(jq -r '.run_at // ""' "$res")" != "$(jq -r '.gate.run_at // ""' "$STATE")" ]] ||
      die "gate-record refused: this result (run_at $(jq -r .run_at "$res")) is already the recorded gate; the gate did not run again (aid-ui-verify.sh without --copy-subject)"
    ck="$(checks_json)"
    rc=0; resolve="$(bpy gate "$STATE" "$ck" "$res")" || rc=$?
    rm -f "$ck"
    [[ "$rc" -eq 0 ]] || exit 1
    jq_write --arg f "$res" --arg sha "$(sha256sum "$res" | cut -d' ' -f1)" --argjson r "$(jq -c '{run_at, build_id}' "$res")" \
      --argjson idx "$resolve" '.gate = {run_at: $r.run_at, result_file: $f, result_sha256: $sha, build_id: $r.build_id}
      | reduce $idx[] as $i (.; .exceptions[$i].resolved = $r.run_at) | .finished = null'
    # the customer page the gate ran over, by sha (end_in_order compares); a new gate forgets finish.json
    cp_sha=""; [[ ! -f "$PROJECT/docs/zakaznik/index.html" ]] || cp_sha="$(sha256sum "$PROJECT/docs/zakaznik/index.html" | cut -d' ' -f1)"
    jq_write --arg s "$cp_sha" '.gate.customer_page_sha256 = (if $s == "" then null else $s end)'
    rm -f "$PROJECT/.aid-ui/finish.json"
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
    # the PM's verdict by the card's value: prevzit (8-10) | vyhrada (6-7, with words) | vratit = no handover
    hv="$(jq -r '.choice as $c | ([.cards[] | select(.id == $c) | .value] | first) // "approve"' <<<"$LIVE_ANSWER")"
    [[ "$hv" != vratit ]] || die "chapter-all refused: the PM returned the web (vratit): fix what the comment names and ask again"
    hband="$(case "$hv" in prevzit) echo "8-10";; vyhrada) echo "6-7";; *) echo "";; esac)"
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
    # the PM's verdict, written once every chapter is taken over (a failed write leaves the state untouched)
    jq_write --arg v "$hv" --arg b "$hband" --arg q "$ANSWER" '.handover = {verdict: $v, rating: (if $b == "" then null else $b end), answer: $q}'
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


  links)
    need_state
    web="$(opt web "$@")"; customer="$(opt customer "$@")"; brand="$(opt brand "$@")"
    [[ -n "$web" && -n "$customer" ]] || usage "links needs --web <url> --customer <url> [--brand <url>]"
    [[ -z "$brand" ]] || url_ok "$brand" || die "links refused: $brand (the brand book) does not answer 200 from this host"
    url_ok "$web" || die "links refused: $web does not answer 200 (after redirects, no login) from this host"
    url_ok "$customer" || die "links refused: $customer does not answer 200 (after redirects, no login) from this host"
    # the web link serves the recorded build's home page and the customer link the customer page - byte for byte
    bdir="$(jq -r '.build.dir // empty' "$STATE")"
    [[ -n "$bdir" && -f "$bdir/index.html" ]] || die "links refused: no recorded build with index.html (build-record first)"
    [[ "$(curl -sS -L --max-time 10 "$web" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$(sha256sum "$bdir/index.html" | cut -d' ' -f1)" ]] ||
      die "links refused: $web does not serve the recorded build's index.html (another site, another build, or a wrapper)"
    [[ -f "$PROJECT/docs/zakaznik/index.html" ]] || die "links refused: no docs/zakaznik/index.html (aid-ui-customer-page.py first)"
    [[ "$(curl -sS -L --max-time 10 "$customer" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$(sha256sum "$PROJECT/docs/zakaznik/index.html" | cut -d' ' -f1)" ]] ||
      die "links refused: $customer does not serve docs/zakaznik/index.html as it is now"
    mkdir -p "$PROJECT/.aid-ui"; tmp="$(tmpfile links.json)"
    jq -n --arg w "$web" --arg c "$customer" --arg b "$brand" --arg at "$(now)" '{web: $w, customer: $c, brand: (if $b == "" then null else $b end), at: $at}' > "$tmp" && mv "$tmp" "$PROJECT/.aid-ui/links.json"
    echo "LINKS: web $web · customer $customer${brand:+ · brand $brand}"
    ;;

  open-item)
    need_state
    sub="${1:-}"; shift || true
    case "$sub" in
      add)
        text="$(opt text "$@")"; owner="$(opt owner "$@")"; due="$(opt due "$@")"; evidence="$(opt evidence "$@")"
        critical=false; for x in "$@"; do [[ "$x" == --critical ]] && critical=true; done
        [[ -n "${text//[[:space:]]/}" && ${#text} -le 500 ]] || usage "open-item add needs --text (1-500 characters)"
        [[ "$owner" =~ ^(PM|klient|agent)$ ]] || usage "open-item add needs --owner PM|klient|agent"
        [[ -z "$due" || "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage "open-item --due is a date YYYY-MM-DD"
        n="$(jq '[.open_items[]? | select(.id | startswith("oi-"))] | length + 1' "$STATE")"
        jq_write --arg id "oi-$n" --arg t "$text" --arg o "$owner" --arg d "$due" --arg at "$(now)" --arg ev "$evidence" --argjson c "$critical" \
          '.open_items += [{id: $id, text: $t, owner: $o, due: (if $d == "" then null else $d end), by: "agent", at: $at, status: "open",
            critical: $c, evidence: (if $ev == "" then null else $ev end)}]'
        echo "OPEN ITEM: oi-$n${critical/false/}"
        ;;
      done)
        id="${1:-}"; [[ -n "$id" ]] || usage "open-item done needs <id> [--evidence <what proves it>]"
        jq -e --arg i "$id" 'any(.open_items[]?; .id == $i)' "$STATE" >/dev/null || die "open-item: no item $id"
        ev="$(opt evidence "$@")"
        if jq -e --arg i "$id" 'any(.open_items[]?; .id == $i and .critical == true)' "$STATE" >/dev/null; then
          [[ -n "${ev//[[:space:]]/}" ]] || die "open-item done refused: $id blocks publication; say what proves it done (--evidence)"
        fi
        jq_write --arg i "$id" --arg at "$(now)" --arg ev "$ev" '.open_items |= map(if .id == $i then .status = "done" | .done_at = $at
          | (if $ev != "" then .done_evidence = $ev else . end) else . end)'
        ;;
      critical)   # H7: mark an item as blocking publication. There is no way back: a block ends only when the
                  # item is done with its evidence (security review 12. 10.: an agent could lift a block by itself)
        id="${1:-}"; [[ -n "$id" ]] || usage "open-item critical needs <id>"
        jq -e --arg i "$id" 'any(.open_items[]?; .id == $i)' "$STATE" >/dev/null || die "open-item: no item $id"
        jq_write --arg i "$id" '.open_items |= map(if .id == $i then .critical = true else . end)'
        ;;
      *) usage "open-item needs add --text <t> --owner <PM|klient|agent> [--due <date>] [--critical] [--evidence <what proves it done>] | critical <id> | done <id> [--evidence <t>]" ;;
    esac
    ;;

  open-items-sync)
    need_state
    # the PM's own items from the studio (POST /open-item -> history.jsonl, by pm, kind open_item): taken over once each
    hist="$PROJECT/.aid-ui/studio/history.jsonl"
    [[ -f "$hist" ]] || { echo "SYNC: 0 new (no history)"; exit 0; }
    # raw lines, fromjson?: a torn or foreign line is skipped, never kills the sync
    new="$(jq -R -c 'fromjson? // empty | select(type == "object" and .by == "pm" and .kind == "open_item" and (.text | type) == "string" and (.at | type) == "string" and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")))
      | {id: ("pm-" + (.at | gsub("[^0-9]"; "") | .[0:20])), text: (.text | .[0:500]), owner: "PM", due: null, by: "pm", at: .at, status: "open"}' "$hist" 2>/dev/null | jq -sc .)"
    cnt="$(jq --argjson n "$new" '[$n[] | .id] - [.open_items[]?.id] | length' "$STATE")"
    jq_write --argjson n "$new" '.open_items = ((.open_items // []) as $have | $have + [$n[] | select(.id as $i | ($have | map(.id) | index($i)) == null)])'
    echo "SYNC: $cnt new open item(s) from the PM"
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
    # last: the links the Hotovo panel shows must still answer (the content, pages and gate are named first)
    lf="$(links_json)"
    web="$(jq -r .web "$lf")"; customer="$(jq -r .customer "$lf")"
    url_ok "$web" || die "finish refused: the web link $web no longer answers 200; serve it, or run links again"
    url_ok "$customer" || die "finish refused: the customer link $customer no longer answers 200; serve it, or run links again"
    jq_write --arg d "$(today)" '.finished = $d'
    # the PM's handover verdict (card prevzit | vyhrada | vratit) and the links the Hotovo panel shows
    verdict="$(jq -r '.handover.verdict // "approve"' "$STATE")"; rating="$(jq -r '.handover.rating // ""' "$STATE")"
    tmp="$(tmpfile finish.json)"
    blocked="$(jq -c '[.open_items[]? | select(.status != "done" and .critical == true) | {id, text, owner}]' "$STATE")"
    jq -n --arg at "$(now)" --arg d "$(today)" --arg w "$web" --arg c "$customer" --arg v "$verdict" --arg r "$rating" --argjson b "$blocked" \
      '{finished: $d, at: $at, web: $w, customer: $c, verdict: $v, rating: (if $r == "" then null else $r end), publish_blocked_by: $b}' > "$tmp" && mv "$tmp" "$PROJECT/.aid-ui/finish.json"
    echo "FINISHED: $(today) · $web · $customer · verdict $verdict${rating:+ ($rating/10)}"
    [[ "$blocked" == "[]" ]] || echo "PUBLISH BLOCKED by $(jq length <<<"$blocked") critical open item(s): $(jq -r 'map(.id) | join(", ")' <<<"$blocked")"
    ;;

  exception-covered)
    need_state
    (( $# == 1 )) && [[ -f "$1" ]] || usage "exception-covered <project> <result.json>"
    bpy covered "$STATE" "$1" "$(dirname "$1")/checks.json"   # warn_only from the checks the gate ran with
    ;;

  context-check)
    need_state
    context_ok || exit 1
    ;;

  method)
    (( $# == 1 )) && [[ "$1" =~ ^[a-z_]+$ ]] || usage "method needs <kind>"
    kind="$1"; map="$HERE/../skills/ui-design/sections.json"
    jq -e --arg k "$kind" '.methods | has($k)' "$map" >/dev/null ||
      usage "method: no kind $kind in the map (kinds: $(jq -r '.methods | keys | join(", ")' "$map"))"
    mkdir -p "$PROJECT/.aid-ui/method"; out="$PROJECT/.aid-ui/method/$kind.json"
    if [[ "$(jq -r --arg k "$kind" '.methods[$k] | type' "$map")" == null ]]; then
      need_state
      # the PM decided on the missing method: a no_method answer, choose, card value pm or without
      w="$(jq -r --arg t "no_method@$kind" 'first(.answers | to_entries[] | .value as $a | select($a.kind == "no_method"
        and $a.target == $t and $a.decision == "choose" and ([$a.cards[]? | select(.id == $a.choice) | .value] | first) as $v
        | $v == "pm" or $v == "without") | .key) // empty' "$STATE")"
      [[ -n "$w" ]] || die "method: no method for $kind (sections.json methods: null). Put a studio question of kind no_method, part = the part you work in, target no_method@$kind, three cards with value: adopt (take over a method and register it), pm (the PM supplies the output: cards then rest on source podklady), without (go on without a method); record-answer it. adopt: register the files in the map and run method again."
      mode="$(jq -r --arg w "$w" '.answers[$w] as $a | [$a.cards[] | select(.id == $a.choice) | .value] | first' "$STATE")"
      jq -n --arg k "$kind" --arg w "$w" --arg m "$mode" --arg at "$(now)" '{kind: $k, files: [], waived: $w, mode: $m, at: $at}' > "$out"
      echo "RECEIPT $out: no method, waived by the PM's answer $w ($mode)"; exit 0
    fi
    files=(); snap="$(tmpfile method)"
    while IFS= read -r f; do
      path="$f"; [[ "$f" == /* ]] || path="$HERE/../$f"
      [[ -f "$path" ]] || die "method: file $f of the $kind method is missing (a standard read live: name it to the PM, MUST 3)"
      cp "$path" "$snap"   # one copy: what is printed is what is hashed
      printf '===== %s\n' "$f"; cat "$snap"; printf '\n'
      files+=("$(jq -n --arg p "$f" --arg s "$(sha256sum "$snap" | cut -d' ' -f1)" '{path: $p, sha256: $s}')")
    done < <(jq -r --arg k "$kind" '.methods[$k].files[]' "$map")
    rm -f "$snap"
    jq -n --arg k "$kind" --arg at "$(now)" --argjson f "[$(IFS=,; echo "${files[*]}")]" '{kind: $k, files: $f, at: $at}' > "$out"
    echo "RECEIPT $out: ${#files[@]} files read at $(jq -r .at "$out"); open the question after this moment, every card with \`method\`"
    ;;

  payload-check)
    (( $# == 0 )) || usage "payload-check takes no arguments"
    python3 "$HERE/../lib/aid-ui-studio/server.py" --check --project "$PROJECT"
    ;;

  copy-record)
    need_state
    (( $# == 1 )) || usage "copy-record <project> <run dir>"
    context_ok >/dev/null || exit 1
    python3 "$HERE/aid-ui-copy.py" record "$PROJECT" "$1" || exit 1
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
    # the step is one of the six of the map (skills/ui-design/sections.json), by title or as "s<n>"
    map="$HERE/../skills/ui-design/sections.json"
    st="$(jq -r --arg s "$step" 'first(.steps[] | select(.title == $s or ("s" + (.n|tostring)) == $s) | .title) // empty' "$map")" ||
      die "decide: $map is not readable JSON"
    [[ -n "$st" ]] || usage "decide: no step \"$step\" in the map (steps: $(jq -r '[.steps[].title] | join(", ")' "$map"))"
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
