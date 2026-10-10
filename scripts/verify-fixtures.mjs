import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const source=JSON.parse(fs.readFileSync('fixtures/SOURCES.json','utf8'));
const [validationText,file]=fs.readFileSync('src/conformance/fixtures_wbtest.mbt','utf8').split('fn official_resources()');
const entries=new Map();
const decode = chunks => [...chunks.matchAll(/"(?:[^"\\]|\\.)*"/g)].map(m=>JSON.parse(m[0])).join('');
const digest = text => crypto.createHash('sha256').update(text).digest('hex');
for(const match of file.matchAll(/\(\s*("(?:[^"\\]|\\.)*"),\s*\[([\s\S]*?)\]\.join\(""\),?\s*\)/g)) {
  entries.set(JSON.parse(match[1]).replace('http://datashapes.org/sh/tests/core/',''),decode(match[2]));
}
assert.equal(entries.size,source.allEmbeddedResources.length);
for(const row of source.allEmbeddedResources)assert.equal(digest(entries.get(row.name)),row.sha256,row.name);
assert.equal(source.validationFiles.length,98);
const validationEntries=new Map([...validationText.matchAll(/\(\s*("(?:[^"\\]|\\.)*"),\s*\[([\s\S]*?)\]\.join\(""\),?\s*\)/g)].map(m=>[JSON.parse(m[1]),decode(m[2])]));
assert.equal(validationEntries.size,98);
for(const row of source.validationFiles)assert.equal(digest(validationEntries.get(row.name)),row.sha256,row.name);
const dcat=fs.readFileSync('fixtures/dcat-ap-3.0.0.ttl','utf8');
const expected=JSON.parse(fs.readFileSync('fixtures/DCAT-SOURCE.json','utf8'));
assert.equal(digest(dcat),expected.sha256);
const embeddedDcat=fs.readFileSync('src/conformance/dcat_wbtest.mbt','utf8').match(/\[([\s\S]*?)\]\.join\(""\)/);
assert.equal(decode(embeddedDcat[1]),dcat);
console.log(`${entries.size} W3C resources and DCAT-AP byte hashes verified.`);
