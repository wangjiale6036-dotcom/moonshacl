import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {moon,moonEnv} from './runtime.mjs';

const release=path.resolve(process.argv[2] || 'artifacts/release');
const manifest=JSON.parse(fs.readFileSync(path.join(release,'manifest.json'),'utf8'));
for(const asset of manifest.assets) {
  assert.equal(path.basename(asset.name),asset.name);
  const bytes=fs.readFileSync(path.join(release,asset.name));
  assert.equal(bytes.length,asset.bytes);
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),asset.sha256);
}
fs.mkdirSync('artifacts',{recursive:true});
const root=fs.mkdtempSync(path.resolve('artifacts/clean install-'));
const env={...moonEnv,MOON_WORK:'off'};
if(path.isAbsolute(moon)) env.PATH=path.dirname(moon)+path.delimiter+process.env.PATH;
function run(binary,args,cwd=root,extra={}) {
  const r=spawnSync(binary,args,{cwd,env:{...env,...extra},encoding:'utf8',maxBuffer:8*1024*1024});
  assert.equal(r.status,0,(r.stdout+r.stderr).slice(-5000));
  return r.stdout;
}
const cliAsset=manifest.assets.find(a=>a.name.endsWith('-cli.tar.gz'));
run('tar',['-xzf',path.join(release,cliAsset.name),'-C',root]);
const cliDir=path.join(root,`moonshacl-${manifest.version}-cli`);
assert(!fs.existsSync(path.join(cliDir,'node_modules')));
assert(!fs.existsSync(path.join(cliDir,'.mooncakes')));
const cli=path.join(cliDir,'cli.mjs');
assert.equal(run(process.execPath,[cli,'--version']).trim(),`MoonSHACL ${manifest.version}`);
const args=['validate',path.join(cliDir,'examples','people-shapes.ttl'),path.join(cliDir,'examples','people-data.ttl')];
assert.equal(JSON.parse(run(process.execPath,[cli,...args])).report.conforms,true);
const dcat=JSON.parse(run(process.execPath,[cli,'validate',path.join(cliDir,'fixtures','dcat-ap-3.0.0.ttl'),path.join(cliDir,'examples','dcat-data.ttl')]));
assert.equal(dcat.report.conforms,true);

const source=path.join(root,'source');fs.mkdirSync(source);
const zip=path.join(release,manifest.assets.find(a=>a.name.endsWith('-source.zip')).name);
if(process.platform==='win32') {
  run('tar',['-xf',zip,'-C',source]);
} else run('unzip',['-q',zip,'-d',source]);
for(const excluded of ['.tools','.mooncakes','audit','node_modules','dist']) assert(!fs.existsSync(path.join(source,excluded)),`${excluded} leaked into source archive`);
run(process.execPath,['scripts/build.mjs'],source);
assert.equal(JSON.parse(run(process.execPath,[path.join(source,'cli.mjs'),'validate',path.join(source,'examples','people-shapes.ttl'),path.join(source,'examples','people-data.ttl')])).report.conforms,true);
fs.writeFileSync('artifacts/release-smoke.json',JSON.stringify({version:manifest.version,sourceCommit:manifest.sourceCommit,platform:process.platform,checks:['asset SHA-256 and size','CLI has no npm or Mooncakes runtime install','CLI runs from a different working directory','CLI reads official DCAT base shapes','source has no private audit or toolchain','clean source builds and validates'],passed:6},null,2)+'\n');
console.log('6/6 clean release installation checks passed.');
