import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {Parser, Store} from 'n3';
import {request} from '../dist/demo/moonshacl.mjs';

const read = file => fs.readFileSync(`dist/demo/${file}`, 'utf8');
const data = JSON.parse(read('demo-data.json'));
const build = JSON.parse(read('build-info.json'));
const run = value => JSON.parse(request(JSON.stringify(value)));
const graph = text => new Store(new Parser().parse(text));
function equalGraph(actual, expected) {
  const a = graph(actual), b = graph(expected);
  assert.equal(a.size, b.size);
  for (const quad of a) assert(b.has(quad), `Unexpected quad: ${JSON.stringify(quad)}`);
}
assert.equal(build.engineSha256, crypto.createHash('sha256').update(read('moonshacl.mjs')).digest('hex'));
for (const asset of ['app.js', 'styles.css', 'worker.js', 'licenses/runtime/moonttl-LICENSE', 'licenses/runtime/moonbit-core-LICENSE', 'licenses/Unicode-DATA-LICENSE.txt']) assert(read(asset).length > 0);
// A standalone demo must retain relative source/evidence links in both reports.
for (const report of ['REAL-DATA.zh-CN.md', 'PERFORMANCE.zh-CN.md', 'docs/REAL-DATA.zh-CN.md', 'docs/PERFORMANCE.zh-CN.md']) {
  if (!fs.existsSync(`dist/demo/${report}`)) continue;
  for (const match of read(report).matchAll(/\]\(([^)]+)\)/g)) {
    const href = match[1];
    if (/^(https?:|#)/.test(href)) continue;
    const url = new URL(href, `file://${process.cwd().replaceAll('\\', '/')}/dist/demo/${report}`);
    assert(fs.existsSync(url), `Broken distributed report link: ${report} -> ${href}`);
  }
}
const p = data.people;
assert.equal(run({shapes: p.shapes, data: p.data}).report.conforms, true);
const reject = run({operation: 'update', shapes: p.shapes, data: p.data, additions: '', removals: p.removals});
assert.equal(reject.committed, false);
equalGraph(reject.graphRdf, p.data);
assert.deepEqual(reject.report.results.map(r => r.focusNode.value).sort(), ['https://example.org/alice', 'https://example.org/bob']);
assert.deepEqual(reject.report.work, {checked: 2, reused: 1});
const apply = run({operation: 'update', shapes: p.shapes, data: reject.graphRdf, additions: p.additions, removals: p.removals});
assert.equal(apply.committed, true);
assert.equal(run({shapes: p.shapes, data: apply.graphRdf}).report.conforms, true);
// Exercise an edit after a successful edit. The demo must use the current graph,
// not silently return to the fixture or attempt to remove an already absent value.
const next = run({operation: 'update', shapes: p.shapes, data: apply.graphRdf, additions: '', removals: p.additions});
assert.equal(next.committed, false);
equalGraph(next.graphRdf, apply.graphRdf);
assert.deepEqual(next.report.results.map(r => r.focusNode.value).sort(), ['https://example.org/alice', 'https://example.org/bob']);
assert.equal(run({shapes: p.shapes, data: '@broken'}).status, 'parse-error');
const checks = ['bundled engine identity and licenses', 'initial graph conforms', 'shared-node deletion rejected with two affected people', 'unaffected root result reused', 'rejection preserves graph', 'atomic rename commits and readback conforms', 'subsequent edit uses latest committed graph', 'invalid input is an execution error'];
if (data.catalogue) {
  const c = data.catalogue;
  assert(c.sourceUrl && c.sourceLabel, 'Public data must retain provenance');
  assert.equal(run({shapes: c.shapes, data: c.data}).report.conforms, true);
  const rejected = run({operation: 'update', shapes: c.shapes, data: c.data, additions: '', removals: c.removals});
  assert.equal(rejected.committed, false);
  equalGraph(rejected.graphRdf, c.data);
  const repaired = run({operation: 'update', shapes: c.shapes, data: c.data, additions: c.additions, removals: c.removals});
  assert.equal(repaired.committed, true);
  assert.equal(run({shapes: c.shapes, data: repaired.graphRdf}).report.conforms, true);
  checks.push('public data provenance retained', 'public catalogue validates against declared application rules', 'injected catalogue deletion rejected', 'catalogue atomic repair commits and validates');
}
fs.mkdirSync('artifacts', {recursive: true});
fs.writeFileSync('artifacts/demo-checks.json', JSON.stringify({executedAt: new Date().toISOString(), engineSha256: build.engineSha256, checks, passed: checks.length, failed: 0, scope: 'Packaged engine and fixture acceptance; browser interactions are checked separately.'}, null, 2) + '\n');
console.log(`${checks.length}/${checks.length} packaged demo acceptance checks passed.`);
