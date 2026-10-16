import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {Parser, Store} from 'n3';

const out=path.resolve(process.argv[2] || 'artifacts/scenarios');
fs.mkdirSync(out,{recursive:true});
const cli=path.resolve('cli.mjs');
function run(name, args, expected) {
  const r=spawnSync(process.execPath,[cli,...args],{encoding:'utf8'});
  assert.equal(r.status,expected,`${name}: ${r.stderr || r.stdout}`);
  const value=JSON.parse(r.stdout || r.stderr);
  fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify(value,null,2)+'\n');
  return value;
}
const read=file=>fs.readFileSync(file,'utf8');
const graph=text=>new Store(new Parser().parse(text));
function sameGraph(a,b) {
  assert.equal(a.size,b.size);
  for(const quad of a) assert(b.has(quad));
}

// A catalogue importer uses real, unchanged published DCAT-AP base shapes.
const dcat=run('01-catalogue-import',['validate','fixtures/dcat-ap-3.0.0.ttl','examples/dcat-data.ttl'],0);
assert.equal(dcat.report.conforms,true);
const missing=run('01-catalogue-rejected',['update','fixtures/dcat-ap-3.0.0.ttl','examples/dcat-data.ttl','examples/empty.ttl','examples/dcat-remove-access-url.ttl'],1);
assert.equal(missing.committed,false);
assert(missing.report.results.some(r=>r.sourceConstraintComponent.endsWith('#MinCountConstraintComponent')));
sameGraph(graph(missing.graphRdf),graph(read('examples/dcat-data.ttl')));

// A metadata editor rejects a shared-node deletion, then commits a replacement.
const rejected=run('02-editor-rejected',['update','examples/people-shapes.ttl','examples/people-data.ttl','examples/empty.ttl','examples/remove-shared-name.ttl'],1);
assert.deepEqual(rejected.report.results.map(r=>r.focusNode.value).sort(),['https://example.org/alice','https://example.org/bob']);
assert.deepEqual(rejected.report.work,{checked:2,reused:1});
sameGraph(graph(rejected.graphRdf),graph(read('examples/people-data.ttl')));
const accepted=run('02-editor-committed',['update','examples/people-shapes.ttl','examples/people-data.ttl','examples/add-shared-name.ttl','examples/remove-shared-name.ttl'],0);
assert.equal(accepted.committed,true);assert.equal(accepted.graphTriples,11);
const saved=path.join(out,'02-editor-export.nt');
fs.writeFileSync(saved,accepted.graphRdf);
const reread=run('02-editor-readback',['validate','examples/people-shapes.ttl',saved],0);
assert.equal(reread.report.conforms,true);
assert(![...graph(accepted.graphRdf)].some(q=>q.object.value==='Acme'));
assert([...graph(accepted.graphRdf)].some(q=>q.object.value==='Acme Limited'));

// A pipeline audits its shape profile before accepting user data.
const supported=run('03-profile-accepted',['audit','examples/people-shapes.ttl'],0);
assert.equal(supported.status,'supported');
const unsupported=run('03-profile-rejected',['validate','examples/unsupported-shapes.ttl','examples/people-data.ttl','--strict'],2);
assert.equal(unsupported.status,'unsupported-or-invalid-shapes');
assert(unsupported.problems.length>0);assert.equal(unsupported.report,undefined);
fs.writeFileSync(path.join(out,'summary.json'),JSON.stringify({scenarios:3,passed:3,scope:'Self-built integration examples; unchanged DCAT base shapes with synthetic data, not external adoption.'},null,2)+'\n');
console.log('3/3 end-to-end acceptance scenarios passed (catalogue import, transactional editor, profile gate).');
