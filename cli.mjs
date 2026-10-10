#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const usage = 'MoonSHACL\n  node cli.mjs audit SHAPES.ttl\n  node cli.mjs validate SHAPES.ttl DATA.ttl [--rdf]\n  node cli.mjs update SHAPES.ttl DATA.ttl ADD.ttl REMOVE.ttl [--rdf]\nExit codes: 0 conforms/committed, 1 nonconforming/rejected update, 2 request/parse/profile error.';
const [command,...args] = process.argv.slice(2);
if (!command || command==='--help') { console.log(usage); process.exit(0); }
try {
  const rdf = args.includes('--rdf');
  const files = args.filter(a=>a!=='--rdf');
  const count = {audit:1,validate:2,update:4}[command];
  if (!count || files.length!==count) throw new Error(usage);
  const request = {operation:command, shapes:fs.readFileSync(files[0],'utf8'), shapesBase:pathToFileURL(path.resolve(files[0])).href};
  if (command!=='audit') { request.data=fs.readFileSync(files[1],'utf8'); request.dataBase=pathToFileURL(path.resolve(files[1])).href; }
  if (command==='update') { request.additions=fs.readFileSync(files[2],'utf8'); request.removals=fs.readFileSync(files[3],'utf8'); }
  const engine = await import(pathToFileURL(path.join(root,'dist/moonshacl.mjs')));
  const result = JSON.parse(engine.request(JSON.stringify(request)));
  console.log(rdf && result.reportRdf ? result.reportRdf : JSON.stringify(result,null,2));
  if (result.status==='supported') process.exit(0);
  if (result.status==='validated') process.exit(result.report.conforms ? 0 : 1);
  if (result.status==='updated') process.exit(result.committed ? 0 : 1);
  process.exit(2);
} catch (error) {
  console.error(JSON.stringify({status:'request-error',message:error.message},null,2));
  process.exit(2);
}
