#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const usage = 'MoonSHACL\n  node cli.mjs --version\n  node cli.mjs audit SHAPES.ttl\n  node cli.mjs validate SHAPES.ttl DATA.ttl [--rdf]\n  node cli.mjs update SHAPES.ttl DATA.ttl ADD.ttl REMOVE.ttl [--rdf]\nOptions: --strict rejects ignored non-Core extensions; --resources MAP.json maps graph IRIs to Turtle file paths (relative to MAP.json). --timezone-minutes N sets the explicit XPath implicit timezone (-840..840). No automatic network fetching.\nUse -- before a filename that begins with a dash.\nExit codes: 0 conforms/committed, 1 nonconforming/rejected update, 2 request/parse/compilation/execution failure.';
const [command,...args] = process.argv.slice(2);
try {
  if (!command || command==='--help' && args.length===0) { console.log(usage); process.exit(0); }
  if (command==='--version' && args.length===0) {
    const metadata = JSON.parse(fs.readFileSync(path.join(root,'package.json'),'utf8'));
    console.log(`MoonSHACL ${metadata.version}`); process.exit(0);
  }
  let rdf=false, strict=false, resourceFile=null, implicitTimezoneMinutes, positionalOnly=false;
  const files=[];
  for (let i=0;i<args.length;i++) {
    const arg=args[i];
    if (!positionalOnly && arg==='--') { positionalOnly=true; continue; }
    if (!positionalOnly && arg==='--rdf') {
      if (rdf || command==='audit') throw new Error('--rdf is supported once for validate/update');
      rdf=true;
    } else if (!positionalOnly && arg==='--strict') {
      if(strict) throw new Error('--strict is supported once');
      strict=true;
    } else if (!positionalOnly && arg==='--resources') {
      if(resourceFile || !args[i+1]) throw new Error('--resources requires one JSON mapping file');
      resourceFile=args[++i];
    } else if (!positionalOnly && arg==='--timezone-minutes') {
      if(implicitTimezoneMinutes!==undefined || !args[i+1]) throw new Error('--timezone-minutes requires one integer in -840..840');
      implicitTimezoneMinutes=Number(args[++i]);
      if(!Number.isInteger(implicitTimezoneMinutes) || Math.abs(implicitTimezoneMinutes)>840) throw new Error('--timezone-minutes requires one integer in -840..840');
    } else if (!positionalOnly && arg.startsWith('-')) {
      throw new Error(`Unknown option: ${arg}`);
    } else files.push(arg);
  }
  const count = {audit:1,validate:2,update:4}[command];
  if (!count || files.length!==count) throw new Error(usage);
  const request = {operation:command, strict, implicitTimezoneMinutes, shapes:fs.readFileSync(files[0],'utf8'), shapesBase:pathToFileURL(path.resolve(files[0])).href};
  if(resourceFile) {
    const mapping=JSON.parse(fs.readFileSync(resourceFile,'utf8'));
    if(!mapping || typeof mapping!=='object' || Array.isArray(mapping)) throw new Error('Resource map must be an object mapping graph IRIs to Turtle file paths');
    request.resources=Object.fromEntries(Object.entries(mapping).map(([iri,file])=>{
      if(typeof file!=='string') throw new Error(`Resource ${iri} requires a file path`);
      return [iri,fs.readFileSync(path.resolve(path.dirname(resourceFile),file),'utf8')];
    }));
  }
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
