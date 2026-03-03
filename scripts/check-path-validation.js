#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const routesDir = path.join(__dirname, '../packages/aid-server/src/routes');
const files = fs.readdirSync(routesDir).filter(f => f.endsWith('.ts'));
let exitCode = 0;
for (const file of files) {
  const content = fs.readFileSync(path.join(routesDir, file), 'utf8');
  const hasRouteParam = /req\.params\.(epicId|runId|id)/.test(content);
  const hasValidation = /isValidPathComponent|validateEpicId|path\.basename/.test(content);
  if (hasRouteParam && !hasValidation) {
    console.error(`FAIL: ${file} reads route params without path validation (CWE-22)`);
    exitCode = 1;
  }
}
process.exit(exitCode);
