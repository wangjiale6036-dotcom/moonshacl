import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {moon, moonEnv} from './runtime.mjs';

// No graph construction, validation, result interpretation, or cache emulation in JS.
// The opaque fixture and every measured operation are implemented in MoonBit.
const args = process.argv.slice(2);
const smoke = args.includes('--smoke');
const value = (flag, fallback) => {
  const index = args.indexOf(flag);
  return index < 0 ? fallback : args[index + 1];
};
const samples = Number(value('--samples', smoke ? '5' : '25'));
const warmups = Number(value('--warmups', smoke ? '1' : '5'));
const diagnosticOutput = value('--output', null);
if (args.includes('--output')) {
  assert(typeof diagnosticOutput === 'string' && diagnosticOutput.endsWith('.json'), '--output needs a .json path');
  const relativeOutput = path.relative(path.resolve('artifacts'), path.resolve(diagnosticOutput));
  assert(relativeOutput && !relativeOutput.startsWith('..') && !path.isAbsolute(relativeOutput),
    '--output diagnostics must be inside artifacts/ to protect the archived formal report');
}
assert(Number.isInteger(samples) && samples >= 5 && samples <= 200, '--samples must be 5..200');
assert(Number.isInteger(warmups) && warmups >= 1 && warmups <= 50, '--warmups must be 1..50');
const modulePath = path.resolve('artifacts/benchmark/core.mjs');
const operations = [
  ['parseDataFresh', 0],
  ['parseShapesFresh', 1],
  ['compileShapes', 2],
  ['validateFullValid', 3],
  ['initializeSession', 4],
  ['previewInvalidCached', 5],
  ['applyInvalidCached', 6],
  ['applyValidCached', 7],
  ['validateFullInvalidPrebuilt', 8],
  ['rebuildAndValidateInvalidFull', 9],
  ['rebuildAndValidateInvalidFullHashed', 10],
];
const memory = () => {
  const {rss, heapUsed, heapTotal, external, arrayBuffers} = process.memoryUsage();
  return {rss, heapUsed, heapTotal, external, arrayBuffers};
};
const summary = raw => {
  const sorted = [...raw].sort((a, b) => a - b);
  const quantile = fraction => sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
  return {medianMs: quantile(.5), p95Ms: quantile(.95), minMs: sorted[0], maxMs: sorted.at(-1), samplesMs: raw};
};

if (args.includes('--worker')) {
  assert(global.gc, 'Worker must run with --expose-gc');
  const core = await import(pathToFileURL(modulePath).href);
  const people = Number(value('--people'));
  const sharing = Number(value('--sharing'));
  const changes = Number(value('--changes'));
  global.gc();
  const baselineAfterGc = memory();
  const f = core.prepare(people, sharing, changes);
  global.gc();
  const fixtureAfterGc = memory();
  const metadata = JSON.parse(core.metadata(f));
  const verificationBefore = JSON.parse(core.verify(f));
  const measurements = {};
  let checksum = 0;
  for (const [name, id] of operations) {
    for (let i = 0; i < warmups; i++) checksum += core.measure(f, id);
    // GC is outside the timed samples. Natural GC during samples stays included.
    global.gc();
    const memoryBefore = memory();
    const raw = [];
    for (let i = 0; i < samples; i++) {
      const start = performance.now();
      checksum += core.measure(f, id);
      raw.push(performance.now() - start);
    }
    measurements[name] = {...summary(raw), memoryBefore, memoryAfter: memory()};
  }
  const verificationAfter = JSON.parse(core.verify(f));
  global.gc();
  const finalAfterGc = memory();
  process.stdout.write(JSON.stringify({
    ...metadata, verificationBefore, verificationAfter, measurements, checksum,
    memory: {baselineAfterGc, fixtureAfterGc, finalAfterGc,
      fixtureHeapDeltaBytes: fixtureAfterGc.heapUsed - baselineAfterGc.heapUsed,
      fixtureRssDeltaBytes: fixtureAfterGc.rss - baselineAfterGc.rss},
  }));
} else {
  const run = (binary, command, options = {}) => {
    const result = spawnSync(binary, command, {encoding: 'utf8', env: moonEnv,
      maxBuffer: 32 * 1024 * 1024, ...options});
    if (result.error || result.status !== 0) {
      throw result.error || new Error(`${binary} ${command.join(' ')} failed:\n${result.stdout}\n${result.stderr}`);
    }
    return result.stdout.trim();
  };
  if (!args.includes('--no-build')) {
    console.log('Building the independent MoonBit JS benchmark package...');
    run(moon, ['build', '--target', 'js', '--release', 'src/benchmark']);
    fs.mkdirSync(path.dirname(modulePath), {recursive: true});
    fs.copyFileSync('_build/js/release/build/benchmark/benchmark.js', modulePath);
  }
  assert(fs.existsSync(modulePath), 'Benchmark module missing; run without --no-build first');
  const sizes = smoke ? [100] : value('--sizes', '100,1000,5000').split(',').map(Number);
  assert(sizes.every(n => Number.isInteger(n) && n >= 100 && n <= 10000 && n % 100 === 0),
    '--sizes must be multiples of 100 from 100 through 10000');
  const walk = directory => fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const filename = `${directory}/${entry.name}`;
    if (entry.isDirectory()) return walk(filename);
    return /\.(mbt|pkg)$/.test(filename) && !/(_test|_wbtest|_test_drivers)\.mbt$/.test(filename) ? [filename] : [];
  });
  const coreFiles = fs.readdirSync('src').filter(name => /\.mbt$/.test(name) && !/(_test|_wbtest)\.mbt$/.test(name)).map(name => `src/${name}`);
  const sourceFiles = [...coreFiles, ...walk('src/benchmark'), ...walk('src/turtle'), ...walk('src/xpath_regex'),
    'src/moon.pkg', 'moon.mod', 'moon.lock', 'scripts/runtime.mjs', 'scripts/benchmark.mjs']
    .filter(filename => fs.existsSync(filename)).sort();
  const hashes = Object.fromEntries(sourceFiles.map(filename => [filename,
    crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex')]));
  const sha256 = crypto.createHash('sha256').update(JSON.stringify(hashes)).digest('hex');
  const startedAt = new Date().toISOString();
  const scenarios = [];
  for (const people of sizes) {
    for (const workload of [
      {name: 'one-person', sharing: 1, changes: 1},
      {name: 'shared-company', sharing: 10, changes: 1},
      {name: 'ten-percent', sharing: 10, changes: Math.max(1, people / 100)},
      {name: 'all-people', sharing: 10, changes: people / 10},
    ]) {
      if (smoke && !['one-person', 'all-people'].includes(workload.name)) continue;
      console.log(`Measuring ${people} people / ${workload.name} (${warmups} warmups, ${samples} samples per operation)...`);
      const raw = run(process.execPath, ['--expose-gc', 'scripts/benchmark.mjs', '--worker',
        '--people', String(people), '--sharing', String(workload.sharing), '--changes', String(workload.changes),
        '--samples', String(samples), '--warmups', String(warmups)], {timeout: 180000});
      const result = JSON.parse(raw);
      assert(result.verificationBefore.passed && result.verificationAfter.passed);
      scenarios.push({name: workload.name, ...result});
    }
  }
  const previousPath = 'docs/evidence/benchmark-before-optimization.json';
  const previousBytes = fs.existsSync(previousPath) ? fs.readFileSync(previousPath) : null;
  const previous = previousBytes ? JSON.parse(previousBytes) : null;
  const previousRoundPath = 'docs/evidence/benchmark-before-round2.json';
  const previousRoundBytes = fs.existsSync(previousRoundPath) ? fs.readFileSync(previousRoundPath) : null;
  const previousRound = previousRoundBytes ? JSON.parse(previousRoundBytes) : null;
  const evidence = {
    schemaVersion: 3, startedAt, finishedAt: new Date().toISOString(),
    command: `node scripts/benchmark.mjs${smoke ? ' --smoke' : ''} --sizes ${sizes.join(',')} --samples ${samples} --warmups ${warmups}${args.includes('--no-build') ? ' --no-build' : ''}${diagnosticOutput ? ` --output ${diagnosticOutput}` : ''}`,
    environment: {platform: process.platform, release: os.release(), arch: process.arch,
      cpu: os.cpus()[0]?.model, logicalCpus: os.cpus().length, totalMemoryBytes: os.totalmem(),
      node: process.version, v8: process.versions.v8, moon: run(moon, ['version']),
      target: 'js', build: 'release', timezone: 'Asia/Shanghai'},
    source: {sha256, files: hashes, compiledModuleSha256: crypto.createHash('sha256').update(fs.readFileSync(modulePath)).digest('hex')},
    methodology: {warmups, samples, scenarioTimeoutSeconds: 180,
      quantiles: 'nearest rank: sorted[ceil(n*p)-1]',
      timing: 'Node performance.now surrounds one exported MoonBit operation; no JSON or report serialization inside timing.',
      session: 'One opaque fixture with one persistent Session per isolated worker; repeated previews and updates reuse that cache. Valid updates alternate old/new values.',
      optimizations: 'Round 1 hashes removals/additions, derives actual changes from supplied deltas and existing graph indexes, and indexes changed Objects/Subjects/Outgoing reads. Preview does not populate a next cache: reused results are still deep-copied, while newly evaluated isolated results are returned directly. Round 2 retains already-unique old triples, visits additions in input order using a first-representative flag and original SPO membership, and calls an internal Graph::from_unique constructor to rebuild SPO/POS indexes without another full-triple deduplication map. Public Graph::new still deduplicates arbitrary input. Reader dependency collection, cache invalidation, target enumeration, and semantic validation remain active, with no full-validation fallback. All candidate construction, changes, dependency checks, and index reconstruction remain timed. All-people has zero reused validation results, so its gain is not semantic-cache reuse alone.',
      cold: 'Fresh parsing and compilation rebuild objects each call; VM/JIT is warmed. OS file I/O, process start, module import and data generation are excluded.',
      fairness: 'Full validation on a prebuilt candidate excludes graph construction. The original rebuildAndValidateInvalidFull comparator is retained unchanged: linear removals.contains filtering, public Graph API construction, and full validation. The primary comparator rebuildAndValidateInvalidFullHashed was introduced in round 1 and is unchanged in round 2: it replaces only the removal lookup with a fresh Map<Triple,Bool>, charging its construction inside the timing. Both full comparators use the same public Graph API and defensive triples() copy, reconstruct all indexes and run full validation. The session uses internal ownership/uniqueness knowledge to omit redundant full-triple deduplication; it still rebuilds indexes and tracks changes and dependencies. Ratios therefore compare complete implementation paths, not isolated semantic-cache benefit. Before/after checks require both candidate triple sequences and full recursive reports to match.',
      memory: 'Bytes from process.memoryUsage snapshots. baseline/fixture/final snapshots follow explicit GC; operation snapshots bracket whole sample batches. No intra-operation peak or allocation-rate measurement. Fixture includes Turtle strings, two graphs, shapes, plan, session/cache and deltas; its delta is not cache-only overhead.',
      gc: 'Explicit GC before sample batches, never inside timed calls; naturally occurring GC remains in sample durations.',
      scope: 'Synthetic Person/company sequence-path workload, not a production dataset, cross-engine ranking or general throughput claim.',
      operations: Object.fromEntries(operations),
    }, historicalComparison: previous ? {
      path: previousPath,
      sha256: crypto.createHash('sha256').update(previousBytes).digest('hex'),
      startedAt: previous.startedAt,
      sourceSha256: previous.source.sha256,
      sameEnvironment: ['platform', 'release', 'arch', 'cpu', 'node', 'v8'].every(key => previous.environment[key] === ({platform: process.platform, release: os.release(), arch: process.arch, cpu: os.cpus()[0]?.model, node: process.version, v8: process.versions.v8})[key]),
      sameSampling: previous.methodology.samples === samples && previous.methodology.warmups === warmups,
      limitation: 'The original pre-optimization archive and current run are separate runs, not randomized paired measurements. Comparison is cache-preview latency against its own prior implementation; the hashed full baseline was introduced in round 1, did not exist in this original archive, and must not be substituted into its old ratios.',
      scenarios: scenarios.map(row => {
        const before = previous.scenarios.find(old => old.people === row.people && old.name === row.name);
        if (!before) return null;
        const oldPreview = before.measurements.previewInvalidCached.medianMs;
        const newPreview = row.measurements.previewInvalidCached.medianMs;
        return {people: row.people, name: row.name,
          wasSlowerThanOriginalFull: before.measurements.rebuildAndValidateInvalidFull.medianMs / oldPreview < 1,
          beforePreviewMedianMs: oldPreview, afterPreviewMedianMs: newPreview,
          previewLatencySpeedup: oldPreview / newPreview,
          previewLatencyReductionPercent: (1 - newPreview / oldPreview) * 100};
      }).filter(Boolean),
    } : null, previousRoundComparison: previousRound ? {
      path: previousRoundPath,
      sha256: crypto.createHash('sha256').update(previousRoundBytes).digest('hex'),
      startedAt: previousRound.startedAt,
      finishedAt: previousRound.finishedAt,
      sourceSha256: previousRound.source.sha256,
      sameEnvironment: ['platform', 'release', 'arch', 'cpu', 'node', 'v8'].every(key => previousRound.environment[key] === ({platform: process.platform, release: os.release(), arch: process.arch, cpu: os.cpus()[0]?.model, node: process.version, v8: process.versions.v8})[key]),
      sameSampling: previousRound.methodology.samples === samples && previousRound.methodology.warmups === warmups,
      baselineOperation: 'rebuildAndValidateInvalidFullHashed',
      limitation: 'The previous-round archive and current run are separate runs, not randomized or interleaved paired measurements. Both already include the same hashed full comparator. Preview self-speedup and the within-run full/preview ratio answer different questions. All-people reuses zero validation results; candidate-construction savings must not be described as semantic-cache reuse.',
      scenarios: scenarios.map(row => {
        const before = previousRound.scenarios.find(old => old.people === row.people && old.name === row.name);
        if (!before) return null;
        const oldPreview = before.measurements.previewInvalidCached.medianMs;
        const newPreview = row.measurements.previewInvalidCached.medianMs;
        const oldFull = before.measurements.rebuildAndValidateInvalidFullHashed.medianMs;
        const newFull = row.measurements.rebuildAndValidateInvalidFullHashed.medianMs;
        return {people: row.people, name: row.name,
          previousWasSlower: oldFull / oldPreview < 1,
          beforePreviewMedianMs: oldPreview, afterPreviewMedianMs: newPreview,
          beforeHashedFullMedianMs: oldFull, afterHashedFullMedianMs: newFull,
          beforeHashedFullToPreviewRatio: oldFull / oldPreview,
          afterHashedFullToPreviewRatio: newFull / newPreview,
          previewLatencySpeedup: oldPreview / newPreview,
          previewLatencyReductionPercent: (1 - newPreview / oldPreview) * 100};
      }).filter(Boolean),
    } : null, scenarios,
  };
  if (diagnosticOutput) {
    fs.mkdirSync(path.dirname(diagnosticOutput), {recursive: true});
    fs.writeFileSync(diagnosticOutput, `${JSON.stringify(evidence, null, 2)}\n`);
    console.log(`Diagnostic checks passed; saved ${diagnosticOutput} (archived report unchanged)`);
  } else if (smoke) {
    fs.mkdirSync('artifacts', {recursive: true});
    fs.writeFileSync('artifacts/benchmark-smoke.json', `${JSON.stringify(evidence, null, 2)}\n`);
    console.log('Smoke checks passed; saved artifacts/benchmark-smoke.json (archived report unchanged)');
  } else {
    fs.mkdirSync('docs/evidence', {recursive: true});
    fs.writeFileSync('docs/evidence/benchmark.json', `${JSON.stringify(evidence, null, 2)}\n`);
    writeReport(evidence);
    console.log('Saved docs/evidence/benchmark.json and docs/PERFORMANCE.zh-CN.md');
  }
}

function writeReport(evidence) {
  const number = value => value.toFixed(3);
  const displayTime = new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  });
  const table = evidence.scenarios.map(row => {
    const m = row.measurements;
    const full = m.rebuildAndValidateInvalidFullHashed.medianMs;
    const originalFull = m.rebuildAndValidateInvalidFull.medianMs;
    const preview = m.previewInvalidCached.medianMs;
    return `| ${row.people} | ${row.name} | ${row.dataTriples} | ${row.affectedPeople}/${row.people} | ${number(originalFull)} | ${number(full)} | ${number(preview)} / ${number(m.previewInvalidCached.p95Ms)} | ${number(m.applyValidCached.medianMs)} | ${(full / preview).toFixed(2)}× |`;
  });
  const phases = evidence.scenarios.filter(row => row.name === 'shared-company').map(row => {
    const m = row.measurements;
    const cell = key => `${number(m[key].medianMs)} / ${number(m[key].p95Ms)}`;
    return `| ${row.people} | ${cell('parseDataFresh')} | ${cell('parseShapesFresh')} | ${cell('compileShapes')} | ${cell('validateFullValid')} | ${cell('initializeSession')} | ${cell('validateFullInvalidPrebuilt')} |`;
  });
  const memoryRows = evidence.scenarios.filter(row => row.name === 'shared-company').map(row => {
    const mib = bytes => (bytes / 1024 / 1024).toFixed(2);
    return `| ${row.people} | ${mib(row.memory.baselineAfterGc.heapUsed)} | ${mib(row.memory.fixtureAfterGc.heapUsed)} | ${mib(row.memory.fixtureHeapDeltaBytes)} | ${mib(row.memory.fixtureAfterGc.rss)} |`;
  });
  const ratios = evidence.scenarios.map(row => row.measurements.rebuildAndValidateInvalidFullHashed.medianMs / row.measurements.previewInvalidCached.medianMs);
  const originalRatios = evidence.scenarios.map(row => row.measurements.rebuildAndValidateInvalidFull.medianMs / row.measurements.previewInvalidCached.medianMs);
  const slower = ratios.filter(value => value < 1).length;
  const comparison = evidence.historicalComparison;
  const originalSlow = comparison?.scenarios.filter(row => row.wasSlowerThanOriginalFull) ?? [];
  const previousRound = evidence.previousRoundComparison;
  const previousSlow = previousRound?.scenarios.filter(row => row.previousWasSlower) ?? [];
  const previousRoundLines = previousRound ? [
    '## 第二轮：上一轮剩余慢场景', '',
    `上一轮证据已保存为 [benchmark-before-round2.json](evidence/benchmark-before-round2.json)，对应报告见 [PERFORMANCE-ROUND1.zh-CN.md](PERFORMANCE-ROUND1.zh-CN.md)。该轮实测时间为 ${displayTime.format(new Date(previousRound.startedAt))} 至 ${displayTime.format(new Date(previousRound.finishedAt))}（北京时间）；证据 SHA-256：\`${previousRound.sha256}\`；被测源码集合 SHA-256：\`${previousRound.sourceSha256}\`。`, '',
    `下表只列上一轮相对哈希全量基线更慢的 ${previousSlow.length} 个场景。环境字段匹配：${previousRound.sameEnvironment ? '是' : '否'}；预热/采样次数匹配：${previousRound.sameSampling ? '是' : '否'}。前后来自独立运行，未作随机交错配对；自身耗时变化也受到系统负载、GC 和 JIT 波动影响。`, '',
    '| 人数 | 场景 | 上轮缓存 median ms | 本轮缓存 median ms | 缓存延迟下降 | 上轮哈希全量 median ms | 本轮哈希全量 median ms | 上轮全量/缓存 | 本轮全量/缓存 |',
    '|---:|---|---:|---:|---:|---:|---:|---:|---:|',
    ...previousSlow.map(row => `| ${row.people} | ${row.name} | ${number(row.beforePreviewMedianMs)} | ${number(row.afterPreviewMedianMs)} | ${row.previewLatencyReductionPercent.toFixed(1)}% | ${number(row.beforeHashedFullMedianMs)} | ${number(row.afterHashedFullMedianMs)} | ${row.beforeHashedFullToPreviewRatio.toFixed(2)}× | ${row.afterHashedFullToPreviewRatio.toFixed(2)}× |`), '',
    '哈希全量基线在上一轮已经加入，本轮保持相同操作、预热、采样和计时边界。缓存自身前后变化与同轮“全量/缓存”比值分开报告，不能互相替代。all-people 的 checked 等于全部目标数、reused 为 0；本轮该场景的改进来自候选图构造等实现成本减少，不是复用了未受影响的校验结果。全部场景均保存在 JSON 的 previousRoundComparison.scenarios 中。', '',
  ] : [];
  const comparisonLines = comparison ? [
    '## 相对首次优化前的累计对照', '',
    `原始证据已保存为 [benchmark-before-optimization.json](evidence/benchmark-before-optimization.json)，原报告见 [PERFORMANCE-BEFORE.zh-CN.md](PERFORMANCE-BEFORE.zh-CN.md)。旧证据 SHA-256：\`${comparison.sha256}\`；旧被测源码集合 SHA-256：\`${comparison.sourceSha256}\`。`, '',
    `以下针对旧版相对原线性删除全量基线更慢的 ${originalSlow.length} 个场景，比的是同一缓存预检操作自身的中位数。环境字段匹配：${comparison.sameEnvironment ? '是' : '否'}；预热/采样次数匹配：${comparison.sameSampling ? '是' : '否'}。前后是不同时间的两次运行，未作随机交错配对，数字仍受调度、GC、JIT 和系统负载影响。`, '',
    '| 人数 | 场景 | 首次优化前缓存 median ms | 当前缓存 median ms | 缓存自身加速比 | 累计延迟下降 |',
    '|---:|---|---:|---:|---:|---:|',
    ...originalSlow.map(row => `| ${row.people} | ${row.name} | ${number(row.beforePreviewMedianMs)} | ${number(row.afterPreviewMedianMs)} | ${row.previewLatencySpeedup.toFixed(2)}× | ${row.previewLatencyReductionPercent.toFixed(1)}% |`), '',
    '哈希全量基线在第一轮优化时加入，首次优化前证据没有这项操作；不能把最初的线性基线比值与当前的哈希基线比值直接相减或称为优化收益。这张表包含两轮实现变化，不代表第二轮单独的改进；全部场景的累计前后缓存中位数与变化百分比均保存在 JSON 的 historicalComparison.scenarios 中。', '',
  ] : [];
  const lines = [
    '# MoonSHACL 性能测量报告', '',
    `实测时间：${displayTime.format(new Date(evidence.startedAt))} 至 ${displayTime.format(new Date(evidence.finishedAt))}（北京时间，Asia/Shanghai，UTC+8）。本报告和原始样本由同一次脚本运行生成；JSON 时间戳保留 UTC。`, '',
    `这次合成负载中，缓存预检相对“哈希删除过滤+重建候选图+全量校验”的中位数比值为 ${Math.min(...ratios).toFixed(2)}–${Math.max(...ratios).toFixed(2)}×，${slower}/${ratios.length} 个场景低于 1×。原线性删除全量基线继续保留，对应比值为 ${Math.min(...originalRatios).toFixed(2)}–${Math.max(...originalRatios).toFixed(2)}×。这里的比值 > 1 表示缓存预检较快，< 1 表示较慢；结论以成本更合理的哈希全量基线为主。`, '',
    '## 复现', '', '```sh', evidence.command.replace(' --no-build', ''), '```', '',
    '默认 100、1,000、5,000 人，每项 5 次预热、25 次采样；每个场景独立 Node 进程，单场景 180 秒上限。可用 `--sizes 100,1000 --samples 25 --warmups 5` 缩小规模。规模限制 100–10,000，必须为 100 的倍数。运行会覆盖本报告和证据 JSON。短探测可指定 `--output artifacts/benchmark-probe.json --samples 5 --warmups 1`，只写诊断 JSON，不更新正式报告。CI 可运行 `node scripts/benchmark.mjs --smoke`：100 人、1 人/全部人受影响两个场景、1 次预热/5 次采样，仅写 `artifacts/benchmark-smoke.json`，不覆盖存档。smoke 或短探测耗时不能替代正式性能结果。', '',
    `环境：${evidence.environment.cpu}；${evidence.environment.platform} ${evidence.environment.release} ${evidence.environment.arch}；Node ${evidence.environment.node}；V8 ${evidence.environment.v8}；MoonBit JS release。`, '',
    '```text', evidence.environment.moon, '```', '',
    `被测源文件 SHA-256 集合摘要：\`${evidence.source.sha256}\`。逐文件摘要、编译产物摘要和完整原始样本见 [benchmark.json](evidence/benchmark.json)。该摘要只覆盖核心、Turtle/正则实现、基准和运行脚本及模块元数据，不包含 UI。`, '',
    '## 测量边界', '',
    '- 图生成、解析、编译、约束执行、Session、候选图创建及一致性检查都在 MoonBit。JavaScript 只负责调度、计时、内存采样和写报告。计时边界内没有 JSON 序列化。',
    '- “新解析”每次重新解析 Turtle 并构建索引；“编译”复用已解析 shapes 并重新创建 Plan。两者有 VM/JIT 预热，不是机器冷启动，均不含读文件、启动进程或导入模块。',
    '- 全量校验复用 Plan；Session 初始化独立计量，包含首次全量校验及依赖缓存建立。每个场景仅创建一个持久 Session 供缓存操作使用；测量中不通过 bridge request 重新初始化 Session。',
    '- 缓存预检删除公司名，应该拒绝；拒绝 apply 也单独计时。成功 apply 在两组公司名之间交替，每次都是真实变化，提交图与缓存。预检和 apply 包括保留原图三元组、对新增三元组去重、索引重建、变化发现、目标重算和缓存检查。本轮利用已有唯一性避免对保留三元组重复建立完整 seen 集合，相关工作仍在计时边界内。预检不填充会被丢弃的下一版缓存；复用旧缓存的结果仍深拷贝，本次新求值且已经隔离的结果直接返回。apply、Session 初始化和 report 保持原缓存及结果隔离行为。',
    '- 原基线 `rebuildAndValidateInvalidFull` 保留逐项 `removals.contains` 的线性删除过滤；改动多时它自身有 O(图三元组×删除条数) 成本。第一轮已加入的主要基线 `rebuildAndValidateInvalidFullHashed` 本轮不变：在每次操作内创建 `Map[Triple,Bool]`，以哈希查询过滤同一组删除，计时包含哈希表构造；其余候选图顺序、公开 Graph API、索引重建和 Plan 全量校验相同。两者的 `triples()` 都会做保护性复制。Session 则利用内部所有权和唯一性知识减少冗余工作，因此速度比反映完整实现路径，并非纯语义缓存收益。',
    '- 另保留预建候选图上的纯全量校验，不能混为端到端提案成本。成功 apply 和拒绝预检的提案不同，因此不计算两者速度比。主要基线不使用 Session、变化发现或缓存；即使改善缓存性能，也必须同这条较强基线比较，避免将旧基线自身的低效计作缓存收益。',
    '- 中位数和 p95 采用最近秩法。预热后、整批采样前强制一次 GC，计时中的自然 GC 保留。阶段顺序固定，每个场景进程独立；单次运行的分位数不等于跨机器或跨运行置信区间。', '',
    '## 本轮实现优化', '',
    '- 第二轮只继续优化 Session 候选图构造：保留的原图三元组已经满足 RDF 集合唯一性；新增数组按输入顺序访问，以哈希表中的标记只处理首个相等代表，再用原图 SPO 索引和删除集合判断是否追加。这样保留“先删除后添加”、原图顺序、首个新增代表及语言标签大小写相等语义，避免对所有保留三元组再次建立 seen 哈希集合。',
    '- 内部 `Graph::from_unique` 接收已证明唯一且由候选图持有的数组，并重新建立全部 SPO/POS 索引。公开 `Graph::new` 仍对任意输入做去重；没有跳过索引、扩大输入假设或改变公开 Graph API。',
    '- 第一轮的删除/添加哈希查询、从提案和原图索引推导真实变化、Objects/Subjects/Outgoing 依赖失效查询继续保留；preview 的 retain_cache=false 和结果隔离也保持不变。依赖读取仍然记录，目标节点每次重新计算，没有停用 Reader 依赖收集或切换到全量 fallback。',
    '- 候选图构造、索引重建、变化发现、目标重算、依赖检查及约束执行均在完整操作计时内；所有正确性检查仍对照独立的全量 Plan.validate。all-people 没有缓存结果复用，本轮收益应解释为构图等实现开销减少。', '',
    '## 负载和正确性', '',
    '合成图每人有类型、姓名、年龄和雇主 4 个三元组，每公司有名称 1 个三元组。规则检查姓名基数/字符串类型、年龄基数/整数类型/范围，以及 `(employer name)` 序列路径的最少值和字符串类型。', '',
    '| 场景 | 共享关系 | 提案 |', '|---|---|---|',
    '| one-person | 每人独立公司 | 改 1 个公司，影响 1 人 |',
    '| shared-company | 10 人共享公司 | 改 1 个公司，影响 10 人 |',
    '| ten-percent | 10 人共享公司 | 改 10% 公司，影响 10% 人；100 人时与 shared-company 相同 |',
    '| all-people | 10 人共享公司 | 改全部公司，影响全部人 |', '',
    '每个场景在测量前后核对：线性与哈希全量基线生成的三元组序列及完整报告一致；缓存预检/拒绝 apply 与全量校验的 conforms 和递归结果数组完全一致；受影响结果数及 checked/reused 符合预期；失败更新保持原图；成功/失败预检均不改变原图；成功提交与全量结果、候选图一致；提交后的缓存报告仍与全量校验一致。计数器不参与语义报告相等比较。任何差异让脚本失败，不能生成成功报告。', '',
    ...previousRoundLines, ...comparisonLines,
    '## 更新成本', '',
    '时间单位毫秒；主要比值为“哈希删除过滤+全量候选图重建+校验中位数 / 缓存预检中位数”。原线性全量列用于保留测量连续性。', '',
    '| 人数 | 场景 | 图三元组 | 复验/目标 | 原线性全量 median | 哈希全量 median | 缓存预检 median / p95 | 成功 apply median | 哈希全量/缓存 |',
    '|---:|---|---:|---:|---:|---:|---:|---:|---:|', ...table, '',
    '## 加载与初始化分解', '',
    '以下取 shared-company 场景，单位毫秒，格式 median / p95。编译固定的同一组 shapes，人数变化不增加规则数。', '',
    '| 人数 | 新解析数据 | 新解析 shapes | 编译 | 全量有效图 | Session 初始化 | 全量预建无效图 |',
    '|---:|---:|---:|---:|---:|---:|---:|', ...phases, '',
    '## 内存采样', '',
    '以下取 shared-company 场景，单位 MiB，样本在显式 GC 后取得。heapUsed 是 V8 已用堆，RSS 是整个进程驻留内存。夹具增量包括输入文本、有效/无效图、索引、shapes、Plan、持久 Session/缓存和变更数组，**不能解释成纯缓存开销**。', '',
    '| 人数 | 基线 heapUsed | 夹具 heapUsed | 夹具 heap 增量 | 夹具 RSS |',
    '|---:|---:|---:|---:|---:|', ...memoryRows, '',
    'JSON 同时保留每批计时前后和全部测量后的 heapUsed、heapTotal、RSS、external、arrayBuffers。采样没有覆盖操作内部瞬时峰值，无法给出峰值内存、每次分配量或缓存容量上限。RSS 还受运行时保留页和 GC 影响，不宜直接作为业务图大小。', '',
    '## 结论与适用范围', '',
    '当前实现通过读取依赖复用未受影响的校验结果；候选图构造、索引、目标枚举和缓存检查仍会消耗时间。因此“只复验少数节点”不能直接等同于“仅付出这些节点的时间”。报告同时保留原线性全量基线和第一轮已加入的哈希全量基线，以区分实现优化与较弱比较对象带来的表面收益。', '',
    '这份报告支持一个有限结论：在本机、这组规则和规模内，存在未受影响目标时，语义缓存减少重复约束执行；全部目标受影响时则没有结果复用。端到端收益还包含候选图构造的优化，由索引重建、目标枚举和改动比例共同决定。它没有证明对所有 SHACL 图或生产数据更快，也没有做跨引擎排名。真实数据示例的正确性与应用价值应单独评估。', '',
    '优化前后的缓存自身延迟对照、当前较强全量基线和完整原始样本共同构成评估依据。扩大规模、路径复杂度或规则数量都需要新证据，不能外推本次数字。', '',
  ];
  fs.writeFileSync('docs/PERFORMANCE.zh-CN.md', lines.join('\n'));
}
