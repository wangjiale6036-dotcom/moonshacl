import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import {moon,moonEnv} from './runtime.mjs';
const result = spawnSync(moon, ['build','--target','js','--release','src/bridge'], {stdio:'inherit',env:moonEnv});
if (result.status !== 0) process.exit(result.status ?? 2);
fs.mkdirSync('dist', {recursive:true});
fs.copyFileSync('_build/js/release/build/bridge/bridge.js', 'dist/moonshacl.mjs');
console.log('Built dist/moonshacl.mjs');
