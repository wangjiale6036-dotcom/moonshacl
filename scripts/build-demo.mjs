import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {moonEnv} from './runtime.mjs';

// The browser ships the exact same MoonBit bridge as the CLI.
if (!process.argv.includes('--skip-engine')) {
  const result = spawnSync(process.execPath, ['scripts/build.mjs'], {stdio: 'inherit'});
  if (result.status !== 0) process.exit(result.status ?? 2);
}
const read = file => fs.readFileSync(file, 'utf8');
const target = path.resolve('dist/demo');
// Replace only this script's generated directory, never the engine or checkout.
const outputRoot = path.resolve('dist');
if (target !== path.join(outputRoot, 'demo') || fs.lstatSync(target, {throwIfNoEntry: false})?.isSymbolicLink()) {
  throw new Error('Unexpected demo output path');
}
fs.rmSync(target, {recursive: true, force: true});
fs.mkdirSync(target, {recursive: true});
for (const file of ['index.html', 'app.js', 'styles.css', 'worker.js']) {
  fs.copyFileSync(`demo/${file}`, path.join(target, file));
}
fs.copyFileSync('dist/moonshacl.mjs', path.join(target, 'moonshacl.mjs'));
const fixture = {
  version: 1,
  people: {
    shapes: read('examples/people-shapes.ttl'),
    data: read('examples/people-data.ttl'),
    removals: read('examples/remove-shared-name.ttl'),
    additions: read('examples/add-shared-name.ttl'),
  },
};
const cataloguePath = 'examples/real-catalogue/scenario.json';
if (fs.existsSync(cataloguePath)) {
  const scenario = JSON.parse(read(cataloguePath));
  fixture.catalogue = {
    ...scenario,
    additions: scenario.additions ?? scenario.repairAdditions,
    currentUrl: scenario.currentUrl ?? scenario.originalAccessUrl,
    replacementUrl: scenario.replacementUrl ?? scenario.replacementAccessUrl,
    officialSummary: scenario.officialSummary ?? {
      conforms: scenario.baseline?.projectedOfficialConforms,
      results: scenario.baseline?.projectedOfficialResults,
      description: '冻结的应用投影按官方 DCAT-AP base 校验。' + (scenario.baseline?.note || ''),
    },
  };
}
fs.writeFileSync(path.join(target, 'demo-data.json'), JSON.stringify(fixture, null, 2) + '\n');
if (fs.existsSync(cataloguePath)) {
  fs.cpSync('examples/real-catalogue', path.join(target, 'examples/real-catalogue'), {recursive: true});
}
for (const [from, to] of [
  ['docs/evidence/benchmark.json', 'performance.json'],
  ['docs/PERFORMANCE.zh-CN.md', 'PERFORMANCE.zh-CN.md'],
  ['docs/PERFORMANCE-BEFORE.zh-CN.md', 'PERFORMANCE-BEFORE.zh-CN.md'],
  ['docs/PERFORMANCE-ROUND1.zh-CN.md', 'PERFORMANCE-ROUND1.zh-CN.md'],
  ['docs/PERFORMANCE-CONFIRMATION.zh-CN.md', 'PERFORMANCE-CONFIRMATION.zh-CN.md'],
  ['docs/evidence/benchmark-before-optimization.json', 'benchmark-before-optimization.json'],
  ['docs/evidence/benchmark-before-round2.json', 'benchmark-before-round2.json'],
  ['docs/evidence/benchmark-round2-confirmation.json', 'benchmark-round2-confirmation.json'],
  ['docs/evidence/real-data.json', 'real-data-evidence.json'],
  ['docs/REAL-DATA.zh-CN.md', 'REAL-DATA.zh-CN.md'],
]) {
  if (fs.existsSync(from)) {
    const canonical = path.join(target, from);
    fs.mkdirSync(path.dirname(canonical), {recursive: true});
    fs.copyFileSync(from, canonical);
    if (from.endsWith('.md')) {
      // Root-level download aliases remain usable outside the source checkout.
      const linked = read(from).replaceAll('](evidence/', '](docs/evidence/').replaceAll('](../examples/', '](examples/');
      fs.writeFileSync(path.join(target, to), linked);
    } else fs.copyFileSync(from, path.join(target, to));
  }
}
fs.cpSync('licenses', path.join(target, 'licenses'), {recursive: true});
for (const file of ['LICENSE', 'NOTICE', 'THIRD_PARTY.md']) fs.copyFileSync(file, path.join(target, file));
// Include licenses for runtime packages actually embedded in the generated module.
const runtime = path.join(target, 'licenses/runtime');
fs.mkdirSync(runtime, {recursive: true});
for (const [dir, label] of [
  ['.mooncakes/thy1016/moonttl', 'moonttl'],
  [path.join(moonEnv.MOON_HOME || path.join(process.env.USERPROFILE || process.env.HOME, '.moon'), 'lib/core'), 'moonbit-core'],
]) {
  if (!fs.existsSync(dir)) continue;
  for (const file of fs.readdirSync(dir)) {
    if (/^(LICENSE|NOTICE|THIRD_PARTY)/i.test(file) && fs.statSync(path.join(dir, file)).isFile()) {
      fs.copyFileSync(path.join(dir, file), path.join(runtime, `${label}-${file}`));
    }
  }
}
for (const file of ['moonttl-LICENSE', 'moonbit-core-LICENSE', 'moonbit-core-NOTICE']) {
  if (!fs.existsSync(path.join(runtime, file))) throw new Error(`Missing browser runtime license: ${file}`);
}
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const manifest = {
  engineVersion: JSON.parse(read('package.json')).version,
  buildKind: 'workspace-source',
  releaseArtifact: false,
  engineSha256: sha256('dist/moonshacl.mjs'),
  inputsSha256: sha256(path.join(target, 'demo-data.json')),
  execution: 'MoonBit-generated ES module in a browser Web Worker; no remote validation service.',
  source: 'https://github.com/wangjiale6036-dotcom/moonshacl',
};
fs.writeFileSync(path.join(target, 'build-info.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Built browser demo: ${target}`);
