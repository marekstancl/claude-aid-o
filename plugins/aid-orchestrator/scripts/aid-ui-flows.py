#!/usr/bin/env python3
"""aid-ui-flows.py - the gate's task scenarios of a web application, generated from its model (P116).

  generate <project> [--dry]
      From docs/design/screens.json (it must pass aid-ui-screens.py check) writes one scenario per task to
      <project>/.aid-ui/scenarios/<task>.mjs and removes a generated scenario whose task left the model (a file the
      generator did not write is never touched). --dry lists what would be written, nothing changes.

A scenario is the module aid-ui-verify.mjs imports for the task's rows: `export const model_sha256` (the model it was
generated from - the gate refuses a scenario of another model) and a default export
async ({page, base, state}) -> {response, done, why}:
  normal     walks the steps (inputs filled into [name=<field>] of the step's screen, the action clicked by
             data-aid-action="<screen>.<action>", a destructive one confirmed by data-aid-confirm-yes="<screen>.<action>"),
             each step on its screen (data-aid-screen), then done_when: the result screen shows the expected text;
  keyboard   the same with Tab and Enter only (a control Tab never reaches fails the row);
  fail-<n>   the failure variant n (aid-ui-screens.py failure_variants): at its step the next document/fetch/xhr
             request fails once (network: aborted, server: 500, validation: 422); the step's screen must still be
             there with every input of the step kept and its recover action present; the recover action is used and the
             task walks on to done_when - a recover that does nothing ends without the result.
done is true only when the result shows; a scenario never throws for a missing result, it says why.
Exit: 0 written, 1 the model is missing or fails check, 2 usage.
"""
import hashlib, importlib.util, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "// aid-ui-flows.py: generated from docs/design/screens.json - do not edit, run aid-ui-flows.py generate"


def screens():
    spec = importlib.util.spec_from_file_location("aid_ui_screens", os.path.join(HERE, "aid-ui-screens.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


RUNTIME = r"""
const S = s => `[data-aid-screen="${s}"]`, A = (s, a) => `[data-aid-action="${s}.${a}"]`, Y = (s, a) => `[data-aid-confirm-yes="${s}.${a}"]`;
async function onScreen(page, s, n) {
  try { await page.locator(S(s)).first().waitFor({ state: 'visible', timeout: 8000 }); }
  catch { throw new Error(`krok ${n}: obrazovka ${s} se neukázala`); }
}
async function tabTo(page, css) {
  for (let i = 0; i < 120; i++) {
    if (await page.evaluate(c => { const a = document.activeElement; return !!a && a.matches(c); }, css)) return;
    await page.keyboard.press('Tab');
  }
  throw new Error(`klávesnicí nedosažitelné: ${css}`);
}
async function fill(page, s, input, kb) {
  for (const [n, v] of Object.entries(input || {})) {
    const css = `${S(s)} [name="${n}"]`;
    if (kb) { await tabTo(page, css); await page.keyboard.press('Control+A'); await page.keyboard.type(v); }
    else await page.locator(css).first().fill(v);
  }
}
async function press(page, s, a, kb) {
  const go = async css => { if (kb) { await tabTo(page, css); await page.keyboard.press('Enter'); } else await page.locator(css).first().click(); };
  await go(A(s, a));
  if (T.kinds[`${s}.${a}`] === 'destructive') await go(Y(s, a));
  await page.waitForLoadState('networkidle').catch(() => {});
}
export default async function ({ page, base, state }) {
  const kb = state === 'keyboard', v = T.variants[state] || null;
  if (!kb && !v && state !== 'normal') throw new Error(`úloha ${T.id} nemá stav scénáře ${state}`);
  const response = await page.goto(new URL(T.steps[0].url.replace(/^\/+/, ''), base).href, { waitUntil: 'networkidle' });
  for (let i = 0; i < T.steps.length; i++) {
    const st = T.steps[i], n = i + 1;
    await onScreen(page, st.screen, n);
    await fill(page, st.screen, st.input, kb);
    if (!v || v.at_step !== n) { await press(page, st.screen, st.action, kb); continue; }
    let hit = false;
    const fail = async route => {
      if (hit || !['document', 'fetch', 'xhr'].includes(route.request().resourceType())) return route.fallback();
      hit = true;
      if (v.kind === 'network') return route.abort('failed');
      return route.fulfill({ status: v.kind === 'validation' ? 422 : 500, contentType: 'text/plain', body: 'aid-ui: vnucené selhání' });
    };
    await page.route('**/*', fail);
    await press(page, st.screen, st.action, false);
    await page.unroute('**/*', fail);
    if (!hit) return { response, done: false, why: `krok ${n}: akce ${st.action} neposlala požadavek, selhání nešlo vnutit` };
    if (!(await page.locator(S(st.screen)).first().isVisible().catch(() => false)))
      return { response, done: false, why: `krok ${n}: po selhání (${v.kind}) zmizela obrazovka ${st.screen} - vstup je pryč` };
    for (const [k, val] of Object.entries(st.input || {})) {
      const cur = await page.locator(`${S(st.screen)} [name="${k}"]`).first().inputValue().catch(() => null);
      if (cur !== val) return { response, done: false, why: `krok ${n}: po selhání (${v.kind}) se ztratil vstup ${k}` };
    }
    if (!(await page.locator(A(st.screen, v.recover)).first().isVisible().catch(() => false)))
      return { response, done: false, why: `krok ${n}: po selhání chybí cesta dál (${st.screen}.${v.recover})` };
    await press(page, st.screen, v.recover, false);
  }
  const scr = page.locator(S(T.done.screen)).first();   // the last action may navigate after its request: wait for it
  const ok = await scr.waitFor({ state: 'visible', timeout: 8000 }).then(() => scr.getByText(T.done.expect).first().waitFor({ state: 'visible', timeout: 5000 }))
    .then(() => true, () => false);
  return { response, done: !!ok, why: ok ? '' : `výsledek nenastal: obrazovka ${T.done.screen} neukazuje „${T.done.expect}“` };
}
"""


def scenario(mod, m, t, sha):
    urls = {s["id"]: mod.screen_url(s) for s in m["screens"]}
    acts = {(s["id"], a["id"]): a for s in m["screens"] for a in s["actions"]}
    plan = {
        "id": t["id"],
        "steps": [{"screen": st["screen"], "action": st["action"], "input": st.get("input") or {}, "url": urls[st["screen"]]} for st in t["steps"]],
        "done": t["done_when"],
        "kinds": {f"{s}.{a}": x["kind"] for (s, a), x in acts.items()},
        "variants": {v["state"]: {"at_step": v["at_step"], "kind": v["kind"], "recover": v["recover"], "generated": v["generated"]}
                     for v in mod.failure_variants(m, t)},
    }
    # model text only as JSON (ASCII-escaped): a title with a line break can never end the comment and inject code
    return (f"{MARK}\n// task {t['id']}: {json.dumps(t['title'])}\nexport const model_sha256 = {json.dumps(sha)};\n"
            f"const T = {json.dumps(plan, ensure_ascii=False)};\n{RUNTIME.lstrip()}")


def generate(proj, dry):
    mod = screens()
    mp = mod.model_path(proj)
    try:
        m = mod.load(proj)
    except (OSError, ValueError) as e:
        print(f"ERROR: aid-ui-flows.py: no readable {mp} ({e}); the scenarios are generated from the model", file=sys.stderr)
        return 1
    bad = mod.violations(m, proj)
    if bad:
        print("ERROR: aid-ui-flows.py: the model fails aid-ui-screens.py check:\n" + "\n".join("screens: " + b for b in bad), file=sys.stderr)
        return 1
    sha = hashlib.sha256(open(mp, "rb").read()).hexdigest()
    out = os.path.join(proj, ".aid-ui", "scenarios")
    want = {f"{t['id']}.mjs": scenario(mod, m, t, sha) for t in m["tasks"]}
    old = []
    if os.path.isdir(out):
        for f in sorted(os.listdir(out)):
            p = os.path.join(out, f)
            if f.endswith(".mjs") and f not in want and os.path.isfile(p) and not os.path.islink(p) \
                    and open(p, encoding="utf-8", errors="replace").readline().rstrip("\n") == MARK:
                old.append(f)
    for f in want:
        print(f"{'would write' if dry else 'wrote'} .aid-ui/scenarios/{f}")
    for f in old:
        print(f"{'would remove' if dry else 'removed'} .aid-ui/scenarios/{f} (its task left the model)")
    if dry:
        return 0
    if os.path.islink(out):
        print(f"ERROR: aid-ui-flows.py: {out} is a symlink; scenarios are written only inside the project", file=sys.stderr)
        return 1
    os.makedirs(out, exist_ok=True)
    for f, text in want.items():
        p = os.path.join(out, f)
        if os.path.islink(p):
            print(f"ERROR: aid-ui-flows.py: {p} is a symlink; not overwritten", file=sys.stderr)
            return 1
        with open(p + ".part", "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(p + ".part", p)
    for f in old:
        os.remove(os.path.join(out, f))
    print(f"FLOWS: {len(want)} scenarios from model {sha[:12]}")
    return 0


def main(a):
    if a and a[0] == "generate" and len(a) in (2, 3) and (len(a) == 2 or a[2] == "--dry") and os.path.isdir(a[1]):
        return generate(os.path.abspath(a[1]), len(a) == 3)
    print("usage: aid-ui-flows.py generate <project> [--dry]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
