#!/usr/bin/env python3
"""aid-ui-copy.py - the independent copy review of /aid-ui (P108, step 7 point 1a).

  python3 aid-ui-copy.py bundle  <project> --subject <subject.json>      prints the run directory
  python3 aid-ui-copy.py run     <run dir> [--stand-in <answer.json> --reason <text>]
  python3 aid-ui-copy.py verdict <run dir>                               prints the verdict JSON
  python3 aid-ui-copy.py record  <project> <run dir>                     (aid-ui-state.sh copy-record)

bundle: a new <project>/.aid-ui/copy/runs/<n>/ holding only what the reviewer may read - the
adopted references/adopted/marketingskills/copy-editing/SKILL.md,
references/adopted/marketingskills/copy-editing/references/checklist.md,
references/adopted/marketingskills/copy-editing/references/plain-english-alternatives.md,
references/adopted/marketingskills/cro/SKILL.md and references/adopted/marketingskills/cro/references/form.md,
references/copy-rules.md, the guides copy-<lang>.md of the languages present, the project's
docs/content/product-context.md and docs/content/facts.yaml, the subject (copy of every page, made
by aid-ui-verify.sh --copy-subject), prompt.md and MANIFEST (sha256 of each file).

run: Codex reads the bundle read-only (codex exec --skip-git-repo-check -s read-only -C <run dir>
-o answer.json, prompt.md on stdin) and run.json records provider, model, command, rc and times.
When Codex gives no answer, the run is recorded as a failed attempt (exit 1). Only then does
--stand-in accept an answer from a Claude subagent with a clean context, and only when the run
directory's timeline.jsonl holds a complete dispatch bracket (aid-emit-dispatch.sh start/complete
--focus copy-review-standin) whose output file is that answer; run.json then says provider claude
and the reason. A run directory written by hand without these records is refused by record.
Stated limit: run.json and subject.json are files; a run directory forged by hand (a fabricated
provider, a subject relabelled with the current build id) is not detected here. The gate row
copy_review compares every page's text with the recorded site again, so a stale subject fails there.

verdict: per page of the subject, recomputed from the answer (a "verdict" the model wrote is
ignored): all seven sweeps of copy-editing (clarity, voice, so_what, prove_it, specificity, emotion,
zero_risk) present and none skipped; the six cro points (value_proposition, headline, cta, trust,
objections, friction) present, status netyka_se only on a page the subject marks legal; every
finding and claim points at a block the page has; no finding of severity blokujici; each of the
five personas of copy-rules.md exactly once, each a number 1-10, none under 5 and the target and sceptical customer at least 7 except on a legal page; every claim names a key of
facts.yaml; a guide copy-<lang>.md exists for the page's language. Pass = none broken.

record: refuses (exit 1, nothing stored) a subject from another build than the recorded one, a run
directory holding a file the bundle does not list, a run without run.json or answer.json, an answer that is
not JSON or breaks references/copy-review.schema.json (the first error named; not counted as a
review), a page not in the subject, a bundle file changed since bundling, a bundle whose facts.yaml
or product-context.md is not the project's current one, a stand-in without its failed Codex attempt
and dispatch bracket, and a fourth failed review of a page in one series (page, facts, context).
Otherwise stores copy_review.pages.<page> in docs/design/brand-state.json atomically; a model
verdict that differs from the recomputed one is noted in <run dir>/verdict.log.
Exit: 0 done, 1 refused, 2 usage.
"""
import argparse, datetime, glob, hashlib, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "skills", "ui-design", "references")
ADOPTED = ["adopted/marketingskills/copy-editing/SKILL.md",
           "adopted/marketingskills/copy-editing/references/checklist.md",
           "adopted/marketingskills/copy-editing/references/plain-english-alternatives.md",
           "adopted/marketingskills/cro/SKILL.md",
           "adopted/marketingskills/cro/references/form.md"]
SWEEPS = ["clarity", "voice", "so_what", "prove_it", "specificity", "emotion", "zero_risk"]
CRO = ["value_proposition", "headline", "cta", "trust", "objections", "friction"]
STANDIN_FOCUS = "copy-review-standin"
PERSONAS = ["konverzní copywriter", "UX písař", "cílový zákazník", "skeptický zákazník", "strážce značky"]
CUSTOMERS = ("cílový zákazník", "skeptický zákazník")   # below 7 the page does not persuade (PM 4. 10. 2026); not on a legal page
# files a run directory may hold besides its MANIFEST: what run, record and the stand-in bracket write
RUN_OUTPUTS = {"MANIFEST", "run.json", "answer.json", "codex.log", "verdict.log", "timeline.jsonl",
               "pending-dispatches.jsonl", "pending-dispatches.jsonl.lock", "standin-answer.json", "claude.log"}

PROMPT = """# Nezávislá kontrola textů webu

Jsi nezávislý revizor textů. Čteš jen soubory v tomto adresáři; nic jiného nemáš a nehledej.

- `subject.json`: texty každé stránky (bloky s id, druhem a textem), jazyk stránky a zda je právní.
- `references/copy-rules.md`: pravidla AID (fakta jen z registru, co blokuje, kotvy skóre person,
  právní stránky). `references/copy-<jazyk>.md`: jazyková příručka.
- `references/adopted/marketingskills/copy-editing/…`: sedm průchodů (Seven Sweeps), kontrolní seznam.
- `references/adopted/marketingskills/cro/…`: rozbor stránky (hodnotová nabídka, nadpis, výzva k akci,
  důvěra, námitky, tření), formuláře.
- `product-context.md`: co víme o produktu a zákaznících. `facts.yaml`: registr faktů.

Pro KAŽDOU stránku ze `subject.json`:

1. Projdi sedm průchodů copy-editing: clarity, voice, so_what, prove_it, specificity, emotion,
   zero_risk. Každý: `status` (`ok` nebo `nalezy`) a `findings` (blok, citace, závažnost
   `blokujici|vazny|drobny` podle `copy-rules.md` „Co blokuje v revizi", návrh opravy).
2. Projdi šest bodů cro: value_proposition, headline, cta, trust, objections, friction (stejný tvar).
   Na právní stránce (`legal: true`) smí bod dostat `status: "netyka_se"` s `reason`.
3. Ohodnoť stránku pěti personami z `copy-rules.md` (konverzní copywriter, UX písař, cílový
   zákazník, skeptický zákazník, strážce značky) skóre 1–10 podle kotev, u každé citace místa.
4. Vypiš každé faktické tvrzení (číslo, jméno, reference, záruka, výsledek, kontakt) s klíčem
   z `facts.yaml`, o který se opírá; když v registru není, `fact_key: null`.

Odpověz JEN jedním objektem JSON podle tohoto tvaru (žádný text okolo):

{"pages": {"<stránka>": {"sweeps": {"clarity": {"status": "ok", "findings": []}, ...},
  "cro": {"value_proposition": {"status": "nalezy", "findings": [{"block": "b3", "text": "…",
  "severity": "vazny", "fix": "…"}]}, ...}, "personas": [{"name": "cílový zákazník", "score": 7,
  "quote": "…"}], "claims": [{"block": "b5", "text": "…", "fact_key": "klienti"}]}}}

Buď přísný k obecným frázím, chybějícímu přínosu pro zákazníka a tvrzením bez faktu; nevymýšlej
nálezy, které text nemá.
"""


def die(msg, code=1):
    print(f"ERROR: aid-ui-copy.py: {msg}", file=sys.stderr)
    sys.exit(code)


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rj(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def wj(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def yaml_json(path):
    r = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"cannot read {path}: {r.stderr.strip()[:200]}")
    return json.loads(r.stdout or "null")


def fact_keys(facts):
    if isinstance(facts, dict):
        return set(map(str, facts))
    if isinstance(facts, list):
        return {str(e.get("claim")) for e in facts if isinstance(e, dict) and e.get("claim") is not None}
    return set()


# ---- bundle -----------------------------------------------------------------------------
def bundle(a):
    proj = os.path.abspath(a.project)
    subject = rj(a.subject)
    ctx = os.path.join(proj, "docs/content/product-context.md")
    facts = os.path.join(proj, "docs/content/facts.yaml")
    for f in (ctx, facts):
        if not os.path.isfile(f):
            die(f"missing {os.path.relpath(f, proj)}")
    runs = os.path.join(proj, ".aid-ui/copy/runs")
    os.makedirs(runs, exist_ok=True)
    n = 1 + max([int(x) for x in os.listdir(runs) if x.isdigit()] or [0])
    d = os.path.join(runs, str(n))
    os.makedirs(d)
    files = list(ADOPTED) + ["copy-rules.md"]
    for lang in sorted({p.get("lang", "") for p in subject.get("pages", {}).values()}):
        if lang and os.path.isfile(os.path.join(REF, f"copy-{lang}.md")):
            files.append(f"copy-{lang}.md")
    for rel in files:
        dst = os.path.join(d, "references", rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(REF, rel), dst)
    shutil.copyfile(ctx, os.path.join(d, "product-context.md"))
    shutil.copyfile(facts, os.path.join(d, "facts.yaml"))
    shutil.copyfile(a.subject, os.path.join(d, "subject.json"))
    with open(os.path.join(d, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(PROMPT)
    lines = []
    for root, _, names in os.walk(d):
        for name in sorted(names):
            p = os.path.join(root, name)
            lines.append(f"{sha(p)}  {os.path.relpath(p, d)}")
    with open(os.path.join(d, "MANIFEST"), "w", encoding="utf-8") as f:
        f.write("\n".join(sorted(lines, key=lambda l: l.split("  ", 1)[1])) + "\n")
    print(d)


def unlisted(d):
    """files in the run directory that neither MANIFEST lists nor run/record/the bracket write"""
    listed = set()
    for line in open(os.path.join(d, "MANIFEST"), encoding="utf-8"):
        rel = line.rstrip("\n").partition("  ")[2]
        if rel:
            listed.add(rel)
    out = []
    for root, dirs, names in os.walk(d):
        for n in dirs + names:
            full = os.path.join(root, n)
            rel = os.path.relpath(full, d)
            if os.path.islink(full):
                out.append(rel + " (symlink)")
            elif n in names and rel not in listed and rel not in RUN_OUTPUTS:
                out.append(rel)
    return sorted(out)


# ---- run --------------------------------------------------------------------------------
def bracket_ok(d, answer):
    """a complete copy-review-standin dispatch bracket in <run dir>/timeline.jsonl whose output is answer"""
    tl = os.path.join(d, "timeline.jsonl")
    if not os.path.isfile(tl):
        return False
    started = done = False
    for line in open(tl, encoding="utf-8"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("focus") != STANDIN_FOCUS:
            continue
        if e.get("event") == "verifier_dispatch_start":
            started = True
        elif e.get("event") == "verifier_dispatch_complete" and started:
            out = e.get("output_file") or ""
            done = done or os.path.realpath(out if os.path.isabs(out) else os.path.join(os.getcwd(), out)) == os.path.realpath(answer)
    return done


def run(a):
    d = os.path.abspath(a.dir)
    if not os.path.isfile(os.path.join(d, "MANIFEST")):
        die(f"{d} is not a bundle (no MANIFEST)", 2)
    runf, ans = os.path.join(d, "run.json"), os.path.join(d, "answer.json")
    extra = unlisted(d)
    if extra:
        die(f"a file the bundle does not list is in the run directory: {extra[0]}; bundle again")
    if a.stand_in:
        if not a.reason:
            die("--stand-in needs --reason", 2)
        rec = rj(runf) if os.path.isfile(runf) else {}
        att = rec.get("codex_attempt") or {}
        if att.get("rc") in (None, 0) and not att.get("no_answer"):
            die("a stand-in is accepted only after a failed Codex attempt in this run (run it without --stand-in first)")
        if not bracket_ok(d, a.stand_in):
            die(f"no complete '{STANDIN_FOCUS}' dispatch bracket for {a.stand_in} in {d}/timeline.jsonl")
        shutil.copyfile(a.stand_in, ans)
        rec.update({"provider": "claude", "model": os.environ.get("AID_UI_STANDIN_MODEL", "claude"), "stand_in_reason": a.reason,
                    "stand_in_source": os.path.abspath(a.stand_in), "rc": 0, "ended_at": now()})
        wj(runf, rec)
        print(f"recorded stand-in answer in {d}")
        return 0
    if os.path.isfile(runf) and (rj(runf).get("provider") or (rj(runf).get("codex_attempt") or {}).get("at")):
        die(f"{d} already has a review run; bundle again for a new review")
    early = [f for f in sorted(RUN_OUTPUTS - {"MANIFEST", "answer.json"}) if os.path.exists(os.path.join(d, f))]
    if early:
        die(f"{early[0]} exists before the review ran; bundle again")
    if os.path.exists(ans):
        os.remove(ans)   # only an answer written by this run counts
    model = os.environ.get("AID_UI_COPY_CODEX_MODEL", "")
    env = {k: v for k, v in os.environ.items() if k != "OPENAI_API_KEY"}   # text never on the API key (PM 12. 10. 2026)
    cmd = ["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-C", d, "-o", ans] + (["-m", model] if model else []) + ["-"]
    started = now()

    def attempt(mode):
        try:
            with open(os.path.join(d, "prompt.md"), encoding="utf-8") as fin, open(os.path.join(d, "codex.log"), mode) as log:
                return subprocess.run(cmd, stdin=fin, stdout=log, stderr=subprocess.STDOUT, env=env,
                                      timeout=int(os.environ.get("AID_UI_COPY_TIMEOUT", "1800"))).returncode
        except (FileNotFoundError, subprocess.TimeoutExpired) as e:
            return 127 if isinstance(e, FileNotFoundError) else 124

    def readable():
        try:
            load_answer(ans); return True
        except (OSError, ValueError):
            return False
    rc = attempt("w")
    tries = 1
    refused = re.search(r"usage limit|quota|rate limit|429|insufficient_quota", open(os.path.join(d, "codex.log"), errors="replace").read()[-4000:], re.I)
    if rc == 0 and not readable() and not refused:   # an empty or unreadable answer: Codex gets one more try
        if os.path.exists(ans):
            os.remove(ans)
        rc = attempt("a"); tries = 2
    no_answer = not (os.path.isfile(ans) and os.path.getsize(ans) > 0)
    rec = {"provider": None if (rc or no_answer) else "codex", "model": model or "codex-default", "command": " ".join(cmd),
           "rc": rc, "started_at": started, "ended_at": now(), "codex_attempt": {"rc": rc, "no_answer": no_answer, "at": started, "tries": tries}}
    wj(runf, rec)
    bad = None
    if not (rc or no_answer):
        try:
            load_answer(ans)   # a schema break stays the review's own failure (verdict/record name it); unreadable JSON is not an answer
        except ValueError as e:
            bad = f"not valid JSON ({e})"
    if rc or no_answer or bad:
        why = f"codex gave no answer (rc {rc})" if (rc or no_answer) else f"codex answer unusable: {bad}"
        if os.environ.get("AID_UI_STANDIN", "on") == "off":
            print(f"{why}; dispatch a stand-in and pass it with --stand-in", file=sys.stderr)
            return 1
        # H2 (PM 12. 10. 2026): the stand-in is wired in - an independent Claude Code with a clean context reads
        # the same bundle; never an API key for text
        ok, note = standin_claude(d, ans, why)
        if not ok:
            rec.update({"stand_in_attempt": note, "ended_at": now()}); wj(runf, rec)
            print(f"{why}; Claude stand-in failed too: {note}", file=sys.stderr)
            return 1
        rec.update({"provider": "claude", "model": os.environ.get("AID_UI_STANDIN_MODEL", "sonnet"), "stand_in_reason": why,
                    "stand_in_source": os.path.join(d, "standin-answer.json"), "rc": 0, "ended_at": now()})
        wj(runf, rec)
        print(f"claude stand-in answered ({why}): {ans}")
        return 0
    print(f"codex answered: {ans}")
    return 0


def standin_claude(d, ans, why):
    """Run the review with an independent Claude Code (clean context, read-only tools, the bundle as cwd), inside
    the dispatch bracket copy-record demands. Writes <d>/standin-answer.json and copies it to answer.json."""
    emit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "aid-emit-dispatch.sh")
    model = os.environ.get("AID_UI_STANDIN_MODEL", "sonnet")
    out = os.path.join(d, "standin-answer.json")
    try:
        subprocess.run(["bash", emit, "start", "--focus", STANDIN_FOCUS, "--agent-id", "aid-orchestrator:copy-review-standin",
                        "--evidence-dir", d], check=True, capture_output=True, text=True, timeout=60)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, f"dispatch bracket start failed: {getattr(e, 'stderr', '') or e}"[:200]
    prompt = open(os.path.join(d, "prompt.md"), encoding="utf-8").read()
    cmd = [os.environ.get("AID_UI_STANDIN_CLAUDE", "claude"), "-p", "--output-format", "json", "--model", model, "--allowedTools", "Read", "Glob", "Grep",
           "--add-dir", d]
    try:
        with open(os.path.join(d, "claude.log"), "w") as log:
            r = subprocess.run(cmd, input=prompt, cwd=d, capture_output=True, text=True,
                               env={k: v for k, v in os.environ.items() if k != "OPENAI_API_KEY"},
                               timeout=int(os.environ.get("AID_UI_COPY_TIMEOUT", "1800")))
            log.write((r.stderr or "")[-4000:])
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return False, "claude not found" if isinstance(e, FileNotFoundError) else "claude timed out"
    text = ""
    try:
        text = json.loads(r.stdout or "{}").get("result") or ""
    except ValueError:
        text = r.stdout or ""
    m = re.search(r"\{.*\}", text, re.S)
    if r.returncode or not m:
        return False, f"claude rc {r.returncode}, no JSON in its answer"
    with open(out, "w", encoding="utf-8") as fo:
        fo.write(m.group(0))
    try:
        load_answer(out)
    except ValueError as e:
        return False, f"claude answer is not valid JSON ({e})"
    try:
        subprocess.run(["bash", emit, "complete", "--focus", STANDIN_FOCUS, "--output-file", out, "--evidence-dir", d],
                       check=True, capture_output=True, text=True, timeout=60)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        return False, f"dispatch bracket complete failed: {getattr(e, 'stderr', '') or e}"[:200]
    shutil.copyfile(out, ans)
    return True, ""


# ---- verdict ----------------------------------------------------------------------------
def load_answer(path):
    text = open(path, encoding="utf-8").read().strip()
    m = re.match(r"^```(?:json)?\s*(.*?)\s*```$", text, re.S)   # a fenced answer is unwrapped
    if m:
        text = m.group(1)
    # a model's answer may end with a stray bracket after a complete value (Coufal 11. 10. 2026, run 4: one
    # extra "}" after 32 KB of valid JSON); the first complete value counts, anything but brackets and
    # whitespace after it does not
    value, end = json.JSONDecoder().raw_decode(text)
    if text[end:].strip(" \t\r\n}]"):
        raise ValueError("extra data after the JSON value")
    return value


def schema_error(answer):
    from jsonschema.validators import Draft202012Validator
    schema = rj(os.path.join(REF, "copy-review.schema.json"))
    errs = sorted(Draft202012Validator(schema).iter_errors(answer), key=lambda e: list(e.path))
    if not errs:
        return None
    e = errs[0]
    return f"{'/'.join(map(str, e.path)) or '(root)'}: {e.message}"


def page_verdict(page, ans, subj, keys):
    bad = []
    if ans is None:
        return ["stránka nemá kontrolu"]
    blocks = {b.get("id") for b in subj.get("blocks") or []}
    for s in SWEEPS:
        part = (ans.get("sweeps") or {}).get(s)
        if part is None:
            bad.append(f"chybí průchod {s}")
        elif part.get("status") == "netyka_se":
            bad.append(f"průchod {s} nelze vynechat (platí na každé stránce)")
    for c in CRO:
        part = (ans.get("cro") or {}).get(c)
        if part is None:
            bad.append(f"chybí bod cro {c}")
        elif part.get("status") == "netyka_se" and not subj.get("legal"):
            bad.append(f"bod cro {c} jako netýká se na stránce, která není právní")
    def known(ref):
        """A block reference as reviewers write it: one id (b7), a list (b1,b3) or a range (b16-b19);
        true when every block it names is on the page (Coufal 9. 10. 2026: Codex wrote ranges, four runs failed on form)."""
        if not isinstance(ref, str) or not ref.strip():
            return False
        for part in re.split(r"[,\s]+", ref.strip()):
            m = re.fullmatch(r"b(\d+)-b?(\d+)", part)
            ids = ["b%d" % i for i in range(int(m.group(1)), int(m.group(2)) + 1)] if m and int(m.group(1)) <= int(m.group(2)) else [part]
            if not ids or any(i not in blocks for i in ids):
                return False
        return True
    for group in ("sweeps", "cro"):
        for name, part in (ans.get(group) or {}).items():
            for f in part.get("findings") or []:
                if not known(f.get("block")):
                    bad.append(f"nález ({name}) odkazuje na blok, který stránka nemá: {f.get('block')}")
                if f.get("severity") == "blokujici":
                    bad.append(f"blokující nález ({name}): {f.get('text', '')[:120]}")
    # the five personas by meaning, not spelling: a reviewer writing Slovak (konverzný copywriter, UX písar,
    # cieľový zákazník, strážca značky) or without diacritics names the same persona
    def canon(n):
        import unicodedata
        s = unicodedata.normalize("NFKD", str(n or "")).encode("ascii", "ignore").decode().lower().strip()
        s = s.replace("konverzny", "konverzni").replace("pisar", "pisar").replace("cielovy", "cilovy").replace("strazca", "strazce")
        for c in PERSONAS:
            cc = unicodedata.normalize("NFKD", c).encode("ascii", "ignore").decode().lower()
            if s == cc or s == cc.replace("pisar", "pisar"):
                return c
        return str(n)
    for p in ans.get("personas") or []:
        if isinstance(p, dict):
            p["name"] = canon(p.get("name"))
    names = [p.get("name") for p in ans.get("personas") or []]
    for n in PERSONAS:
        if names.count(n) != 1:
            bad.append(f"persona {n}: {'chybí' if n not in names else 'víckrát'}")
    for n in sorted({x for x in names if x not in PERSONAS}, key=str):
        bad.append(f"persona {n}: není mezi pěti personami copy-rules.md")
    for p in ans.get("personas") or []:
        sc = p.get("score")
        if not (isinstance(sc, int) and not isinstance(sc, bool) and 1 <= sc <= 10):
            bad.append(f"persona {p.get('name')}: skóre není číslo 1-10 ({sc!r})")
        elif sc < 5:
            bad.append(f"persona {p.get('name')}: skóre {sc}")
        elif sc < 7 and p.get("name") in CUSTOMERS and not subj.get("legal"):
            bad.append(f"persona {p.get('name')}: skóre {sc} - zákazníka to nepřesvědčí (stránka potřebuje aspoň 7)")
    for c in ans.get("claims") or []:
        if not known(c.get("block")):
            bad.append(f"tvrzení odkazuje na blok, který stránka nemá: {c.get('block')}")
        if not c.get("fact_key") or str(c.get("fact_key")) not in keys:
            bad.append(f"tvrzení bez faktu v registru: {c.get('text', '')[:120]}")
    lang = subj.get("lang", "")
    if not lang or not os.path.isfile(os.path.join(REF, f"copy-{lang}.md")):
        bad.append(f"bez jazykové příručky ({lang or 'jazyk neuveden'})")
    return bad


def compute(d):
    subject = rj(os.path.join(d, "subject.json"))
    answer = load_answer(os.path.join(d, "answer.json"))
    keys = fact_keys(yaml_json(os.path.join(d, "facts.yaml")))
    pages = (answer.get("pages") or {}) if isinstance(answer, dict) else {}
    out = {}
    for p, subj in subject.get("pages", {}).items():
        bad = page_verdict(p, pages.get(p), subj, keys)
        out[p] = {"verdict": "fail" if bad else "pass", "blocking": bad,
                  "scores": {x.get("name"): x.get("score") for x in (pages.get(p) or {}).get("personas") or []},
                  "lang_guide": os.path.isfile(os.path.join(REF, f"copy-{subj.get('lang', '')}.md"))}
    return answer, out


def verdict(a):
    d = os.path.abspath(a.dir)
    try:
        _, out = compute(d)
    except (ValueError, OSError) as e:
        die(f"answer unreadable: {e}")
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


# ---- record -----------------------------------------------------------------------------
def record(a):
    proj, d = os.path.abspath(a.project), os.path.abspath(a.dir)
    runf, ansf = os.path.join(d, "run.json"), os.path.join(d, "answer.json")
    if not os.path.isfile(runf):
        die("no run.json: run the review with aid-ui-copy.py run")
    if not os.path.isfile(ansf):
        die("no answer.json in the run")
    run_rec = rj(runf)
    if run_rec.get("provider") not in ("codex", "claude"):
        die("run.json records no answering provider")
    if run_rec["provider"] == "claude":
        att = run_rec.get("codex_attempt") or {}
        if att.get("rc") in (None, 0) and not att.get("no_answer"):
            die("a stand-in answer without a failed Codex attempt")
        if not bracket_ok(d, run_rec.get("stand_in_source", "")):
            die(f"a stand-in answer without its '{STANDIN_FOCUS}' dispatch bracket")
    try:
        answer = load_answer(ansf)
    except ValueError as e:
        die(f"the answer is not valid JSON ({e}); not counted as a review")
    err = schema_error(answer)
    if err:
        die(f"the answer breaks copy-review.schema.json at {err}; not counted as a review")
    subject = rj(os.path.join(d, "subject.json"))
    build = ((rj(os.path.join(proj, "docs/design/brand-state.json")).get("build")) or {}).get("id")
    if subject.get("build_id") != build:
        die("the subject is from another build than the one recorded now; make the subject again (aid-ui-verify.sh --copy-subject)")
    out_of_bundle = unlisted(d)
    if out_of_bundle:
        die(f"a file the bundle does not list is in the run directory: {out_of_bundle[0]}")
    extra = sorted(set(answer.get("pages", {})) - set(subject.get("pages", {})))
    if extra:
        die(f"the answer reviews a page not in the subject: {extra[0]}")
    man = {}
    for line in open(os.path.join(d, "MANIFEST"), encoding="utf-8"):
        h, _, rel = line.rstrip("\n").partition("  ")
        if rel:
            man[rel] = h
    for rel, h in man.items():
        p = os.path.join(d, rel)
        if not os.path.isfile(p) or sha(p) != h:
            die(f"bundle file changed since bundling: {rel}")
    for rel, cur in (("facts.yaml", "docs/content/facts.yaml"), ("product-context.md", "docs/content/product-context.md")):
        if man.get(rel) != sha(os.path.join(proj, cur)):
            die(f"the bundle's {rel} is not the project's current {cur}; bundle again")
    _, out = compute(d)
    # H6 (12. 10. 2026): a phrase the client quoted when returning the texts must not come back anywhere - body,
    # title, description, og, alt; checked here, without a model (Coufal: "ceny vopred" came back in meta and OG)
    for p, hit in rejected_hits(rj(os.path.join(proj, "docs/design/brand-state.json")), subject).items():
        if p in out:
            out[p]["verdict"] = "fail"
            out[p]["blocking"] = [f"věta vrácená klientem se vrátila: „{h}“" for h in hit] + out[p]["blocking"]
    model_v = (answer.get("verdict") if isinstance(answer, dict) else None)
    if model_v is not None:
        with open(os.path.join(d, "verdict.log"), "a", encoding="utf-8") as f:
            f.write(f"{now()} model verdict ignored: {json.dumps(model_v, ensure_ascii=False)[:500]}\n")
    stp = os.path.join(proj, "docs/design/brand-state.json")
    st = rj(stp)
    prev = (st.get("copy_review") or {}).get("pages") or {}
    fsha, csha = man["facts.yaml"], man["product-context.md"]
    bsha = sha(os.path.join(d, "MANIFEST"))
    new = {}
    for p, v in out.items():
        old = prev.get(p) or {}
        same = old.get("facts_sha256") == fsha and old.get("context_sha256") == csha
        failed = old.get("failed_reviews", 0) if same else 0
        if v["verdict"] == "fail":
            if failed >= 3:
                die(f"{p}: a fourth failed review in this series; ask the PM for an exception (studio exception, check copy_review)")
            failed += 1
        new[p] = {"subject_sha256": subject["pages"][p]["sha256"], "facts_sha256": fsha, "context_sha256": csha,
                  "bundle_sha256": bsha, "provider": run_rec["provider"], "model": run_rec.get("model"), "at": now(),
                  "failed_reviews": failed, "verdict": v["verdict"], "blocking": v["blocking"], "scores": v["scores"],
                  "lang_guide": v["lang_guide"], "run": os.path.relpath(d, proj)}
    st.setdefault("copy_review", {}).setdefault("pages", {}).update(new)
    wj(stp, st)
    for p, v in new.items():
        print(f"{v['verdict'].upper()} {p}" + (f": {'; '.join(v['blocking'][:3])}" if v["blocking"] else ""))
    return 0


QUOTED = re.compile(r"„([^“”\"]{4,120})[“”]|\"([^\"]{4,120})\"")


def norm(t):
    return re.sub(r"\s+", " ", (t or "").replace("\u00a0", " ").replace("–", "-")).strip().lower()


def rejected_phrases(st):
    """phrases the client quoted in a returned copy_verdict comment (Slovak/Czech „…“ or straight quotes)"""
    out = []
    for a in (st.get("answers") or {}).values():
        if isinstance(a, dict) and a.get("kind") == "copy_verdict" and a.get("decision") == "return":
            for m in QUOTED.finditer(a.get("comment") or ""):
                ph = norm(m.group(1) or m.group(2))
                if ph and ph not in out:
                    out.append(ph)
    return out


def rejected_hits(st, subject):
    """page -> the rejected phrases found in any of its blocks (every block kind counts)"""
    phs, hits = rejected_phrases(st), {}
    for p, v in (subject.get("pages") or {}).items():
        text = " \n ".join(norm(b.get("text")) for b in v.get("blocks") or [])
        found = [ph for ph in phs if ph in text]
        if found:
            hits[p] = found
    return hits


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="verb", required=True)
    b = sub.add_parser("bundle"); b.add_argument("project"); b.add_argument("--subject", required=True)
    r = sub.add_parser("run"); r.add_argument("dir"); r.add_argument("--stand-in"); r.add_argument("--reason")
    v = sub.add_parser("verdict"); v.add_argument("dir")
    c = sub.add_parser("record"); c.add_argument("project"); c.add_argument("dir")
    a = ap.parse_args()
    return {"bundle": bundle, "run": run, "verdict": verdict, "record": record}[a.verb](a) or 0


if __name__ == "__main__":
    sys.exit(main())
