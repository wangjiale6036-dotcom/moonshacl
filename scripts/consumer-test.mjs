import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {moon,moonEnv} from './runtime.mjs';

const registry=process.argv.includes('--registry');
const version=JSON.parse(fs.readFileSync('package.json','utf8')).version;
assert(fs.readFileSync('examples/consumer/moon.mod','utf8').includes(`"wangjiale6036-dotcom/moonshacl@${version}"`));
fs.mkdirSync('artifacts',{recursive:true});
const root=fs.mkdtempSync(path.resolve('artifacts/consumer-'));
const consumer=path.join(root,'consumer');
fs.cpSync('examples/consumer',consumer,{recursive:true,filter:src=>!src.split(path.sep).some(p=>['_build','.mooncakes'].includes(p))});
const env={...moonEnv,MOON_WORK:'off'};
if(!registry) {
  const workspace=path.join(root,'moon.work');
  fs.writeFileSync(workspace,`members = [${[path.resolve('.'),consumer].map(p=>JSON.stringify(p.replaceAll('\\','/'))).join(', ')}]\n`);
  env.MOON_WORK=workspace;
}
function run(args) {
  const r=spawnSync(moon,['-C',consumer,...args],{env,encoding:'utf8',maxBuffer:4*1024*1024});
  assert.equal(r.status,0,(r.stdout+r.stderr).split(/\r?\n/).filter(l=>l.length<1000).slice(-30).join('\n'));
  return r.stdout+r.stderr;
}
if(registry) run(['update']);
const backends=[];
for(const target of ['js','wasm-gc','native']) {
  const output=run(['test','--package','moonshacl-examples/consumer','--target',target,'--deny-warn']);
  assert(/Total tests: 1, passed: 1, failed: 0/.test(output),output.slice(-2000));
  backends.push({target,passed:1,failed:0});
}
fs.writeFileSync(`artifacts/consumer-${registry?'registry':'source'}.json`,JSON.stringify({mode:registry?'registry':'source-workspace',module:`wangjiale6036-dotcom/moonshacl@${version}`,backends},null,2)+'\n');
console.log(`Independent ${registry?'registry':'source'} consumer: 3/3 backends passed.`);
