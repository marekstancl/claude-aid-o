// aid-ui-map-render.mjs — draw a process map ONCE into an SVG (P118, /ecosystem/specs/procesni-mapy).
//   node aid-ui-map-render.mjs <drawing.bpmn|drawing.mmd> <out.svg> <step ids comma-separated>
// bpmn-js (navigated viewer) imports the BPMN XML our builder laid out and saves its SVG; Mermaid renders the
// stateDiagram text. Both libraries come from this directory's node_modules (package-lock pins them) and are
// injected from disk: the page makes no network request. Every step id must be findable in the SVG
// (data-element-id for BPMN, the s_<id> node id for Mermaid), else exit 1 render_missing_id — the clickable
// page needs them. Exit: 0 written, 1 render failure, 2 usage.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const [src, out, idsArg] = process.argv.slice(2);
if (!src || !out || idsArg === undefined || !/\.(bpmn|mmd)$/.test(src)) {
  console.error('usage: aid-ui-map-render.mjs <drawing.bpmn|drawing.mmd> <out.svg> <ids,comma,separated>');
  process.exit(2);
}
const kind = src.endsWith('.bpmn') ? 'bpmn' : 'stav';
const text = fs.readFileSync(src, 'utf8');
const ids = idsArg.split(',').filter(Boolean);
const lib = kind === 'bpmn'
  ? path.join(here, 'node_modules/bpmn-js/dist/bpmn-navigated-viewer.production.min.js')
  : path.join(here, 'node_modules/mermaid/dist/mermaid.min.js');
const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
try {
  const page = await browser.newPage();
  await page.route('**/*', r => r.request().url().startsWith('data:') ? r.continue() : r.abort());
  await page.setContent('<!doctype html><html><body><div id="c" style="width:6000px;height:4000px"></div></body></html>');
  await page.addScriptTag({ path: lib });
  const svg = await page.evaluate(async ({ kind, text }) => {
    if (kind === 'bpmn') {
      const viewer = new window.BpmnJS({ container: '#c' });
      const res = await viewer.importXML(text);
      if (res.warnings.length) throw new Error('bpmn warnings: ' + res.warnings.map(w => w.message).join('; '));
      return (await viewer.saveSVG()).svg;
    }
    window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'base',
      themeVariables: { fontFamily: 'system-ui, -apple-system, "Segoe UI", sans-serif', primaryColor: '#ffffff',
        primaryBorderColor: '#1f2937', lineColor: '#4b5563', textColor: '#1f2937', edgeLabelBackground: '#ffffff' } });
    return (await window.mermaid.render('mapa', text)).svg;
  }, { kind, text });
  const missing = ids.filter(id => kind === 'bpmn'
    ? !svg.includes(`data-element-id="${id}"`)
    : !new RegExp(`id="[^"]*\\bs_${id}\\b`).test(svg));
  if (missing.length) { console.error(`render_missing_id: ${missing.join(' ')}`); process.exit(1); }
  fs.writeFileSync(out, svg);
  console.log(out);
} catch (e) {
  console.error(`render_failed: ${e.message}`);
  process.exit(1);
} finally {
  await browser.close();
}
