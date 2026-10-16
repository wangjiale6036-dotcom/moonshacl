import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import path from 'node:path';
import vm from 'node:vm';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {moon, moonEnv} from './runtime.mjs';
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

// Pin every imported regex data input. These checks are independent of whether
// any individual test happens to exercise an altered Unicode range or case.
const unicode = JSON.parse(fs.readFileSync('fixtures/regex-unicode/SOURCES.json','utf8'));
assert.equal(unicode.version, '15.0.0');
assert.deepEqual(unicode.inputs.map(row => row.name), ['UnicodeData.txt','Blocks.txt','SpecialCasing.txt']);
for (const row of unicode.inputs) {
  assert.equal(row.url, `https://www.unicode.org/Public/15.0.0/ucd/${row.name}`);
  assert.equal(digest(fs.readFileSync(`fixtures/regex-unicode/${row.name}`)), row.sha256, row.name);
}
const qt3 = JSON.parse(fs.readFileSync('fixtures/regex-w3c-source.json','utf8'));
assert.equal(qt3.repository, 'https://github.com/w3c/qt3tests');
assert.equal(qt3.commit, '201a6e466940cdfc727f4babfedcde5332b9f578');
assert.equal(digest(fs.readFileSync('fixtures/regex-w3c-matches.xml')), qt3.sha256, 'QT3 matches.xml');
assert.equal(digest(fs.readFileSync('fixtures/regex-w3c-perl-tests.xml')), qt3.regression.sha256, 'QT3 perl-tests.xml');
assert.equal(qt3.selected.length, 146);
assert.equal(qt3.excluded.length, 20);
assert.equal(qt3.regression.selected.length, 1542);
assert.equal(qt3.regression.excluded.length, 117);
for (const [selected, excluded, sourcePath, expression] of [
  [qt3.selected, qt3.excluded, 'fixtures/regex-w3c-matches.xml', /<test-case\s+name="([^"]+)"/g],
  [qt3.regression.selected, qt3.regression.excluded, 'fixtures/regex-w3c-perl-tests.xml', /<test\s+id="([^"]+)"/g],
]) {
  const sourceNames = [...fs.readFileSync(sourcePath, 'utf8').matchAll(expression)].map(m=>m[1]);
  const named = [...selected, ...excluded.map(row => row.name)];
  assert.equal(new Set(named).size, named.length, `${sourcePath}: duplicate accounting`);
  assert.deepEqual(named.toSorted(), sourceNames.toSorted(), `${sourcePath}: unaccounted cases`);
}
for (const [manifest, base] of [[unicode, 'fixtures/regex-unicode'], [qt3, 'fixtures']]) {
  const licensePath = path.resolve(base, manifest.license);
  assert(fs.existsSync(licensePath), `${base}: missing redistribution license`);
  assert(fs.readFileSync(licensePath, 'utf8').includes('Permission'), `${base}: license text is incomplete`);
}

// Re-execute the checked-in generators in an isolated, synchronous context with
// a read-only virtual filesystem. writeFileSync captures bytes in memory, so
// verification never rewrites a fixture, source, manifest, or temporary file.
// Import syntax is restricted to the two built-ins these generators actually
// use. The context exposes neither process, networking, nor arbitrary modules.
const generated = new Map();
const root = process.cwd();
const resolve = value => path.resolve(value instanceof URL ? fileURLToPath(value) : value);
const allowedReads = new Set([
  ...unicode.inputs.map(row=>path.resolve('fixtures/regex-unicode',row.name)),
  path.resolve('fixtures/regex-w3c-matches.xml'),
  path.resolve('fixtures/regex-w3c-perl-tests.xml'),
  path.resolve('fixtures/regex-w3c-source.json'),
]);
const allowedWrites = new Set([
  'src/xpath_regex/unicode_generated.mbt',
  'fixtures/regex-unicode/SOURCES.json',
  'src/xpath_regex/w3c_generated_test.mbt',
  'src/xpath_regex/w3c_regression_generated_test.mbt',
  'fixtures/regex-w3c-source.json',
].map(file=>path.resolve(file)));
const virtualFs = {
  readFileSync(value, encoding) {
    const file = resolve(value);
    assert(allowedReads.has(file), `Generator attempted unexpected read: ${path.relative(root,file)}`);
    const bytes = generated.has(file) ? Buffer.from(generated.get(file)) : fs.readFileSync(file);
    return encoding ? bytes.toString(encoding) : bytes;
  },
  writeFileSync(value, data) {
    const file = resolve(value);
    assert(allowedWrites.has(file), `Generator attempted unexpected write: ${path.relative(root,file)}`);
    generated.set(file, typeof data === 'string' ? data : Buffer.from(data).toString('utf8'));
  },
};
for (const script of ['scripts/generate-regex-unicode.mjs','fixtures/regex-generate-w3c.mjs']) {
  const code = fs.readFileSync(script, 'utf8').replace(/^import (fs|crypto) from 'node:(fs|crypto)';\r?\n/gm, '')
    .replaceAll('import.meta.url', 'generatorUrl');
  assert(!/^import /m.test(code), `${script}: unexpected new import must be audited`);
  vm.runInNewContext(code, {
    fs:virtualFs, crypto, URL, generatorUrl:pathToFileURL(path.resolve(script)).href,
    console:{log(){}},
  }, {filename:script, timeout:30000});
}
assert.equal(generated.size, allowedWrites.size, 'Missing generated artifacts');
const formatter = moon === 'moon' ? (process.platform === 'win32' ? 'moonfmt.exe' : 'moonfmt')
  : path.join(path.dirname(moon), process.platform === 'win32' ? 'moonfmt.exe' : 'moonfmt');
for (const [file, expectedText] of generated) {
  const actual = fs.readFileSync(file, 'utf8');
  if (file.endsWith('.json')) {
    assert.deepEqual(JSON.parse(actual), JSON.parse(expectedText), `${path.relative(root,file)} differs from its generator`);
  } else {
    const formatted = spawnSync(formatter, ['-'], {input:expectedText, encoding:'utf8', env:moonEnv, maxBuffer:16*1024*1024});
    assert.ifError(formatted.error);
    assert.equal(formatted.status, 0, `${formatter} failed: ${formatted.stderr}`);
    assert.equal(actual.replaceAll('\r\n','\n'), formatted.stdout.replaceAll('\r\n','\n'), `${path.relative(root,file)} differs from its generator`);
  }
}
console.log(`${entries.size} W3C resources, DCAT-AP, Unicode 15 inputs/tables, and 1688 QT3 regex cases verified; regeneration matched without file writes.`);
