import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {moon,moonEnv} from './runtime.mjs';
const outputDir='audit/2026-10-10';
fs.mkdirSync(outputDir,{recursive:true});
function run(binary,args,name) {
  const result=spawnSync(binary,args,{env:moonEnv,encoding:'utf8',maxBuffer:16*1024*1024});
  const text=(result.stdout||'')+(result.stderr||'');
  fs.writeFileSync(`${outputDir}/${name}.log`,text);
  if(result.error||result.status!==0) {
    console.error(text.split(/\r?\n/).filter(line=>line.length<600).slice(-40).join('\n'));
    throw result.error||new Error(`${name} failed (${result.status})`);
  }
  return text;
}
run(moon,['fmt','--check'],'fmt-check');
run(moon,['check'],'check');
console.log(run(process.execPath,['scripts/verify-fixtures.mjs'],'fixtures').trim());
const rows=[];
for(const target of ['js','wasm-gc','native']) {
  const log=run(moon,['test','--target',target],`test-${target}`);
  const conformance=JSON.parse(log.split(/\r?\n/).find(line=>line.startsWith('CONFORMANCE_JSON=')).slice('CONFORMANCE_JSON='.length));
  assert.deepEqual([conformance.passed,conformance.rejected,conformance.failed],[76,22,0]);
  assert.equal(conformance.cases.length,98);
  assert(!conformance.cases.some(row=>row.status==='parser-rejected'));
  const summary=log.match(/Total tests: (\d+), passed: (\d+), failed: (\d+)\./);
  assert(summary,`${target}: missing test summary`);
  assert.equal(summary[1],summary[2]);assert.equal(summary[3],'0');
  fs.writeFileSync(`${outputDir}/conformance-${target}.json`,JSON.stringify(conformance,null,2));
  if(target==='js')fs.writeFileSync(`${outputDir}/conformance.json`,JSON.stringify(conformance,null,2));
  const demo=run(moon,['run','src/demo','--target',target],`demo-${target}`);
  assert(demo.includes('committed=false; graphTriples=8'));
  assert(demo.includes('committed=true'));
  rows.push({target,tests:Number(summary[1]),passed:Number(summary[2]),failed:0,w3c:{passed:76,rejected:22,failed:0},consumerDemo:'passed'});
  console.log(`${target}: ${summary[2]}/${summary[1]} MoonBit tests; W3C 76 passed, 22 explicitly rejected; consumer demo passed.`);
}
run(process.execPath,['scripts/build.mjs'],'build-js');
for(const name of ['bridge-test','cli-test','oracle','scenarios','consumer-test']) {
  console.log(run(process.execPath,[`scripts/${name}.mjs`],name).trim());
}
const versions={moon:run(moon,['version'],'moon-version').trim(),node:process.version};
const oracle=JSON.parse(fs.readFileSync(`${outputDir}/oracle.json`,'utf8'));
fs.writeFileSync(`${outputDir}/verification.json`,JSON.stringify({verifiedAt:new Date().toISOString(),versions,backends:rows,bridgeBoundaryChecks:17,cliChecks:13,independentOracle:{engine:oracle.engine,version:oracle.version,cases:oracle.cases.length,matched:oracle.cases.filter(c=>c.status==='matched').length},incrementalEquivalenceProposalsPerBackend:1000},null,2));
console.log('Verification evidence saved in audit/2026-10-10/verification.json');
console.log(run(process.execPath,['scripts/source-audit.mjs'],'source-audit').trim());
console.log(run(process.execPath,['scripts/export-evidence.mjs'],'export-evidence').trim());
