import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const cases = [
  [0,['audit','examples/people-shapes.ttl']],
  [0,['validate','examples/people-shapes.ttl','examples/people-data.ttl']],
  [1,['update','examples/people-shapes.ttl','examples/people-data.ttl','examples/empty.ttl','examples/remove-shared-name.ttl']],
  [0,['update','examples/people-shapes.ttl','examples/people-data.ttl','examples/add-shared-name.ttl','examples/remove-shared-name.ttl']],
  [0,['validate','fixtures/dcat-ap-3.0.0.ttl','examples/dcat-data.ttl']],
  [1,['update','fixtures/dcat-ap-3.0.0.ttl','examples/dcat-data.ttl','examples/empty.ttl','examples/dcat-remove-access-url.ttl']],
  [2,['validate','examples/unsupported-shapes.ttl','examples/people-data.ttl','--strict']],
  [0,['validate','examples/unsupported-shapes.ttl','examples/people-data.ttl']],
  [2,['validate','examples/missing.ttl','examples/people-data.ttl']],
  [2,['audit','examples/people-shapes.ttl','--rdf']],
  [2,['validate','examples/people-shapes.ttl','examples/people-data.ttl','--rdf','--rdf']],
  [2,['validate','examples/people-shapes.ttl','examples/people-data.ttl','--unknown']],
  [0,['validate','--','examples/people-shapes.ttl','examples/people-data.ttl']],
  [0,['validate','examples/imports/root.ttl','examples/imports/data.ttl','--resources','examples/imports/resources.json']],
  [2,['validate','examples/imports/root.ttl','examples/imports/data.ttl']],
  [2,['audit','examples/people-shapes.ttl','--timezone-minutes','841']],
  [0,['audit','examples/people-shapes.ttl','--timezone-minutes','-480']],
];
for (const [expected,args] of cases) {
  const r=spawnSync(process.execPath,['cli.mjs',...args],{encoding:'utf8'});
  assert.equal(r.status,expected,`${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
  const output=JSON.parse(r.stdout||r.stderr);
  if (args[0]==='update') assert.equal(output.committed,expected===0);
  if (args[0]==='update'&&expected===1&&args[1].includes('people')) {
    assert.equal(output.report.results.length,2);
    assert.equal(output.report.work.checked,2);
    assert.equal(output.report.work.reused,1);
    assert.equal(output.graphTriples,11);
  }
}
const version=spawnSync(process.execPath,['cli.mjs','--version'],{encoding:'utf8'});
assert.equal(version.status,0);assert.equal(version.stdout.trim(),`MoonSHACL ${JSON.parse(fs.readFileSync('package.json','utf8')).version}`);
fs.mkdirSync('artifacts',{recursive:true});
fs.writeFileSync('artifacts/cli-checks.json',JSON.stringify({checks:cases.length+1,passed:cases.length+1,failed:0},null,2)+'\n');
console.log(`${cases.length+1}/${cases.length+1} CLI checks passed.`);
