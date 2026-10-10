import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
const root = 'audit/2026-10-10/external/w3c-data-shapes/data-shapes-test-suite/tests/core';
function walk(dir) { return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]); }
const files = walk(root).filter(f => f.endsWith('.ttl') && !path.basename(f).startsWith('manifest'));
const lines = ['// Generated from unchanged W3C fixtures. See fixtures/SOURCES.json and licenses/.', '', 'fn official_fixtures() -> Array[(String, String)] {', '  ['];
const sources = [];
const resourceSources = [];
const resources = [];
function mbtString(s) {
  const chars = [...s], chunks = [];
  for (let i=0; i<chars.length; i+=110) chunks.push(JSON.stringify(chars.slice(i,i+110).join('')));
  return '[\n' + chunks.map(c=>'      '+c+',').join('\n') + '\n    ].join("")';
}
for (const file of files.sort()) {
  const name = path.relative(root, file).replaceAll('\\', '/');
  // Read Git blobs so Windows checkout CRLF conversion cannot change fixtures.
  const content = execFileSync('git',['-C','audit/2026-10-10/external/w3c-data-shapes','show','HEAD:data-shapes-test-suite/tests/core/'+name],{encoding:'utf8'});
  resourceSources.push({name,sha256:crypto.createHash('sha256').update(content).digest('hex')});
  resources.push(`    (${JSON.stringify('http://datashapes.org/sh/tests/core/' + name)}, ${mbtString(content)}),`);
  if (!content.includes('sht:Validate')) continue;
  lines.push(`    (${JSON.stringify(name)}, ${mbtString(content)}),`);
  sources.push({ name, sha256: crypto.createHash('sha256').update(content).digest('hex') });
}
lines.push('  ]', '}');
lines.push('fn official_resources() -> Map[String, String] { Map([', ...resources, ']) }');
fs.mkdirSync('fixtures', {recursive:true});
fs.mkdirSync('src/conformance', {recursive:true});
fs.mkdirSync('licenses', {recursive:true});
fs.writeFileSync('src/conformance/fixtures_wbtest.mbt', lines.join('\n'));
const w3cCommit = execFileSync('git',['-C','audit/2026-10-10/external/w3c-data-shapes','rev-parse','HEAD'],{encoding:'utf8'}).trim();
fs.writeFileSync('fixtures/SOURCES.json', JSON.stringify({ repository:'https://github.com/w3c/data-shapes', commit:w3cCommit, validationFiles:sources, allEmbeddedResources:resourceSources }, null, 2));
fs.copyFileSync('audit/2026-10-10/external/w3c-data-shapes/LICENSE.md','licenses/W3C-repository-LICENSE.md');
fs.copyFileSync('audit/2026-10-10/external/dcat-ap/LICENSE','licenses/DCAT-AP-CC-BY-4.0.txt');
const dcat = execFileSync('git',['-C','audit/2026-10-10/external/dcat-ap','show','HEAD:releases/3.0.0/shacl/dcat-ap-SHACL.ttl'],{encoding:'utf8'});
fs.writeFileSync('fixtures/dcat-ap-3.0.0.ttl',dcat);
const dcatCommit = execFileSync('git',['-C','audit/2026-10-10/external/dcat-ap','rev-parse','HEAD'],{encoding:'utf8'}).trim();
fs.writeFileSync('fixtures/DCAT-SOURCE.json',JSON.stringify({repository:'https://github.com/SEMICeu/DCAT-AP',commit:dcatCommit,path:'releases/3.0.0/shacl/dcat-ap-SHACL.ttl',sha256:crypto.createHash('sha256').update(dcat).digest('hex'),license:'CC-BY-4.0'},null,2));
fs.writeFileSync('src/conformance/dcat_wbtest.mbt', `// Unchanged official DCAT-AP 3.0.0 base shapes, CC BY 4.0.\n\nfn dcat_shapes_text() -> String { ${mbtString(dcat)} }\n`);
console.log(`Embedded ${sources.length} unchanged W3C validation fixtures and official DCAT-AP shapes.`);
