import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

const out=process.argv.includes('--snapshot')?'docs/evidence':'artifacts/evidence';
const read=name=>JSON.parse(fs.readFileSync(name,'utf8'));
const audit='audit/2026-10-10';
const verification=read(`${audit}/verification.json`);
assert(verification.backends.every(b=>b.failed===0 && b.w3c.failed===0));
const conformance=read(`${audit}/conformance.json`);
const oracle=read(`${audit}/oracle.json`);
assert.equal(conformance.failed,0);
assert(oracle.cases.every(c=>c.status==='matched'));
const revision=spawnSync('git',['rev-parse','HEAD'],{encoding:'utf8'});
// git archive expands SOURCE_REVISION; a source zip also supports npm test.
const archived=fs.existsSync('SOURCE_REVISION')?fs.readFileSync('SOURCE_REVISION','utf8').trim():'';
const sourceRevision=/^[a-f0-9]{40}$/.test(archived)?archived:revision.status===0?revision.stdout.trim():null;
const source=read('artifacts/source-audit.json');
const scenarios=read('artifacts/scenarios/summary.json');
const consumer=read('artifacts/consumer-source.json');
const files={
  'verification.json':{sourceRevision,platform:process.platform,architecture:process.arch,...verification,scenarios,consumer},
  'conformance.json':{passed:conformance.passed,rejected:conformance.rejected,failed:conformance.failed,cases:conformance.cases.map(c=>({name:c.name,status:c.status,...(c.errors?{reasons:c.errors.map(e=>({predicate:e.predicate,message:e.message}))}:{})}))},
  'oracle.json':oracle,
  'source-audit.json':source,
};
fs.mkdirSync(out,{recursive:true});
for(const [name,value] of Object.entries(files)) fs.writeFileSync(path.join(out,name),JSON.stringify(value,null,2)+'\n');
console.log(`Exported ${Object.keys(files).length} allowlisted evidence files to ${out}.`);
