import {spawnSync} from 'node:child_process';
import {moon,moonEnv} from './runtime.mjs';
const result=spawnSync(moon,process.argv.slice(2),{env:moonEnv,stdio:'inherit'});
if(result.error){console.error(result.error.message);process.exit(2);}
process.exit(result.status??2);
