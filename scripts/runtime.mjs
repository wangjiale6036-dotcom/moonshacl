import fs from 'node:fs';
import path from 'node:path';
const local = path.resolve('.tools/moon');
const binary = path.join(local,'bin',process.platform==='win32'?'moon.exe':'moon');
export const moon = fs.existsSync(binary) ? binary : 'moon';
export const moonEnv = fs.existsSync(binary) ? {...process.env,MOON_HOME:local} : process.env;
