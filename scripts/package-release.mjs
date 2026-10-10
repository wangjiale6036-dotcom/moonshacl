import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {moonEnv} from './runtime.mjs';

const metadata=JSON.parse(fs.readFileSync('package.json','utf8'));
const version=metadata.version;
assert(/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version));
assert(fs.readFileSync('moon.mod','utf8').includes(`version = "${version}"`));
function run(command,args) {
  const result=spawnSync(command,args,{encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  return result.stdout.trim();
}
assert.equal(run('git',['status','--porcelain','--untracked-files=normal']),'','Commit all release inputs before packaging');
run(process.execPath,['scripts/build.mjs']);
const out=path.resolve('artifacts/release');
fs.mkdirSync(out,{recursive:true});
const staging=fs.mkdtempSync(path.join(out,'staging-'));
const name=`moonshacl-${version}-cli`;
const bundle=path.join(staging,name);
fs.mkdirSync(bundle);
for(const entry of ['cli.mjs','dist','examples','fixtures','licenses','LICENSE','NOTICE','THIRD_PARTY.md','README.md','docs']) {
  fs.cpSync(entry,path.join(bundle,entry),{recursive:true,filter:src=>!src.split(path.sep).some(p=>['_build','.mooncakes'].includes(p))});
}
fs.writeFileSync(path.join(bundle,'package.json'),JSON.stringify({name:'moonshacl-cli',version,private:true,type:'module'},null,2)+'\n');
fs.writeFileSync(path.join(bundle,'RUN.md'),'# MoonSHACL '+version+' CLI\n\nRequires Node.js 24+. No npm installation or MoonBit compiler is needed.\n\n```sh\nnode cli.mjs --version\nnode cli.mjs validate examples/people-shapes.ttl examples/people-data.ttl\nnode cli.mjs validate fixtures/dcat-ap-3.0.0.ttl examples/dcat-data.ttl\n```\n\nSee README.md and docs/PROFILE.md for commands and limitations.\n');
const bundled=path.join(bundle,'licenses','runtime');fs.mkdirSync(bundled,{recursive:true});
function copyLicenses(dir,label) {
  if(!fs.existsSync(dir)) return;
  for(const file of fs.readdirSync(dir)) if(/^(LICENSE|NOTICE|THIRD_PARTY)/i.test(file) && fs.statSync(path.join(dir,file)).isFile()) fs.copyFileSync(path.join(dir,file),path.join(bundled,`${label}-${file}`));
}
for(const owner of fs.readdirSync('.mooncakes',{withFileTypes:true}).filter(d=>d.isDirectory())) {
  for(const mod of fs.readdirSync(path.join('.mooncakes',owner.name),{withFileTypes:true}).filter(d=>d.isDirectory())) copyLicenses(path.join('.mooncakes',owner.name,mod.name),`${owner.name}-${mod.name}`);
}
const home=moonEnv.MOON_HOME || path.join(process.env.HOME || process.env.USERPROFILE,'.moon');
copyLicenses(path.join(home,'lib','core'),'moonbit-core');
assert(fs.readdirSync(bundled).some(n=>n.startsWith('thy1016-moonttl-')),'MoonTTL license is required');
assert(fs.readdirSync(bundled).some(n=>n.startsWith('moonbit-core-')),'Core license is required');
const cliName=name+'.tar.gz';
run('tar',['-czf',path.join(out,cliName),'-C',staging,name]);
const sourceName=`moonshacl-${version}-source.zip`;
run('git',['archive','--format=zip',`--output=${path.join(out,sourceName)}`,'HEAD']);
const sourceCommit=run('git',['rev-parse','HEAD']);
const assets=[sourceName,cliName].map(name=>({name,bytes:fs.statSync(path.join(out,name)).size,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(out,name))).digest('hex')}));
fs.writeFileSync(path.join(out,'SHA256SUMS'),assets.map(a=>`${a.sha256}  ${a.name}`).join('\n')+'\n');
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({version,sourceCommit,assets},null,2)+'\n');
console.log(JSON.stringify({version,sourceCommit,assets},null,2));
