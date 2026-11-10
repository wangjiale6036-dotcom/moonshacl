import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {Parser, Store, Writer, DataFactory} from 'n3';
import {request} from '../dist/moonshacl.mjs';

// This verifier is deliberately offline. The frozen SPARQL response is the source
// of every imported statement; --write-fixture only regenerates local derivatives.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const directory = path.join(root, 'examples/real-catalogue');
const read = name => fs.readFileSync(path.join(directory, name), 'utf8');
const writeJson = (filename, value) => fs.writeFileSync(filename, JSON.stringify(value, null, 2) + '\n');
const sha256 = value => createHash('sha256').update(value).digest('hex');
const graph = value => new Store(new Parser().parse(value));
const run = value => JSON.parse(request(JSON.stringify(value)));
const {namedNode, quad} = DataFactory;
const dcat = 'http://www.w3.org/ns/dcat#';
const dct = 'http://purl.org/dc/terms/';
const rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
const source = JSON.parse(read('SOURCES.json'));
const original = read('source-response.ttl');
const originalGraph = graph(original);
const shapes = read('application-shapes.ttl');
const baseShapes = fs.readFileSync(path.join(root, source.officialProfile.file), 'utf8');
let checks = 0;
function check(label, actual, expected = true) {
  assert.deepEqual(actual, expected, label);
  checks++;
}
function sameGraph(label, a, b) {
  check(label, a.size === b.size && [...a].every(q => b.has(q)));
}
function serialize(quads) {
  const writer = new Writer({format:'N-Triples'});
  writer.addQuads([...quads].sort((a,b) => JSON.stringify(a.toJSON()).localeCompare(JSON.stringify(b.toJSON()), 'en')));
  return new Promise((resolve,reject) => writer.end((error,text) => error ? reject(error) : resolve(text)));
}
check('frozen response SHA-256', sha256(original), source.response.sha256);
check('frozen response byte length', Buffer.byteLength(original), source.response.bytes);
check('source query SHA-256', sha256(read('source-query.rq')), source.query.sha256);
check('official profile SHA-256', sha256(baseShapes), source.officialProfile.sha256);
check('source response triple count', originalGraph.size, source.response.triples);

// Extract a documented projection without adding facts or repairing source data.
const dataset = namedNode(source.datasetIri);
const distributionIds = originalGraph.getObjects(dataset, namedNode(dcat+'distribution'), null);
check('nonempty source distributions', distributionIds.length > 0);
check('all source distribution identifiers are IRIs', distributionIds.every(x => x.termType === 'NamedNode'));
const datasetPredicates = new Set([rdf+'type', dct+'title', dct+'description', dcat+'distribution']);
const distributionPredicates = new Set([rdf+'type', dcat+'accessURL', dcat+'downloadURL', dct+'format', dct+'license', dcat+'mediaType']);
const distributionSet = new Set(distributionIds.map(x => x.value));
const imported = new Store([...originalGraph].filter(q => {
  const selected = q.subject.equals(dataset) ? datasetPredicates.has(q.predicate.value)
    : distributionSet.has(q.subject.value) && distributionPredicates.has(q.predicate.value);
  return selected && (q.object.termType !== 'Literal' || q.object.language === '' || q.object.language === 'en');
}));
check('the projection is a strict subset of real source triples', imported.size > 0 && imported.size < originalGraph.size && [...imported].every(q => originalGraph.has(q)));
check('no blank nodes, contact details or synthetic triples in the projection', [...imported].every(q => q.subject.termType === 'NamedNode' && q.object.termType !== 'BlankNode' && !/mailto:|tel:/i.test(q.object.value)));
const data = '# Unmodified statements projected from the frozen data.europa.eu response.\n' + await serialize(imported);
const distribution = namedNode(source.transaction.distributionIri);
const accesses = imported.getQuads(distribution, namedNode(dcat+'accessURL'), null, null);
const downloads = imported.getObjects(distribution, namedNode(dcat+'downloadURL'), null);
check('chosen CSV distribution has exactly one original access URL', accesses.length, 1);
check('chosen CSV distribution has exactly one published download URL', downloads.length, 1);
check('replacement is the published download IRI and changes the working graph', downloads[0].termType === 'NamedNode' && !downloads[0].equals(accesses[0].object));
const removed = accesses[0];
const added = quad(distribution, namedNode(dcat+'accessURL'), downloads[0]);
const removals = '# Deliberate error injection: do not apply this to the source portal.\n' + await serialize([removed]);
const repairAdditions = '# Local import policy: expose the already published CSV download as the access entry.\n' + await serialize([added]);

const rawOfficial = run({data: original, shapes:baseShapes, strict:true});
const projectedOfficial = run({data, shapes:baseShapes, strict:true});
check('raw official validation executes', rawOfficial.status, 'validated');
check('projected official validation executes', projectedOfficial.status, 'validated');
check('raw official result remains explicit', rawOfficial.report.conforms, source.expected.rawOfficialConforms);
check('raw official violation count remains explicit', rawOfficial.report.results.length, source.expected.rawOfficialResults);
check('projection official result remains explicit', projectedOfficial.report.conforms, source.expected.projectedOfficialConforms);
check('projection official violation count remains explicit', projectedOfficial.report.results.length, source.expected.projectedOfficialResults);
check('all official results concern absent linked-resource classes in this graph slice', [...rawOfficial.report.results, ...projectedOfficial.report.results].every(x => x.sourceConstraintComponent.endsWith('#ClassConstraintComponent')));
const originalApplication = run({data: original, shapes, strict:true});
const importedApplication = run({data, shapes, strict:true});
check('unmodified source satisfies the local application profile', originalApplication.status === 'validated' && originalApplication.report.conforms);
check('imported projection satisfies the local application profile', importedApplication.status === 'validated' && importedApplication.report.conforms);
check('application profile has no ignored extensions', importedApplication.diagnostics, []);

const candidateGraph = new Store([...imported]);
candidateGraph.removeQuad(removed);
const broken = run({data:await serialize(candidateGraph), shapes, strict:true});
check('deliberately broken candidate really violates the profile', broken.status === 'validated' && !broken.report.conforms);
const rejected = run({operation:'update', data, shapes, additions:'', removals, strict:true});
check('invalid update is rejected', rejected.committed, false);
check('rejection explains the missing access URL', rejected.report.results.some(x => x.focusNode.value === distribution.value && x.sourceConstraintComponent.endsWith('#MinCountConstraintComponent') && x.resultPath?.predicate === dcat+'accessURL'));
check('linked dataset is also reported', rejected.report.results.some(x => x.focusNode.value === dataset.value && x.sourceConstraintComponent.endsWith('#NodeConstraintComponent')));
check('only the affected distribution and its dataset are reported', [...new Set(rejected.report.results.map(x => x.focusNode.value))].sort(), [distribution.value,dataset.value].sort());
sameGraph('failed transaction preserves every imported triple', graph(rejected.graphRdf), imported);

const accepted = run({operation:'update', data:rejected.graphRdf, shapes, additions:repairAdditions, removals, strict:true});
check('corrected atomic replacement commits', accepted.committed, true);
check('corrected candidate conforms', accepted.report.conforms, true);
const finalGraph = graph(accepted.graphRdf);
const expectedGraph = new Store([...imported]);
expectedGraph.removeQuad(removed); expectedGraph.addQuad(added);
sameGraph('commit changes exactly the intended access triple', finalGraph, expectedGraph);
check('old access triple is removed', finalGraph.has(removed), false);
check('new access URL comes from the frozen official download URL', originalGraph.has(quad(distribution,namedNode(dcat+'downloadURL'),added.object)) && finalGraph.has(added));
check('commit is not a no-op', [...imported].some(q => !finalGraph.has(q)) && [...finalGraph].some(q => !imported.has(q)));
const outputDirectory = path.join(root,'artifacts/real-catalogue');
fs.mkdirSync(outputDirectory,{recursive:true});
fs.writeFileSync(path.join(outputDirectory,'committed.nt'),accepted.graphRdf);
const exported = fs.readFileSync(path.join(outputDirectory,'committed.nt'),'utf8');
sameGraph('exported file preserves the committed graph', graph(exported), finalGraph);
const readback = run({data:exported, shapes, strict:true});
check('committed graph reads back from disk and conforms', readback.status === 'validated' && readback.report.conforms);
check('source bytes remain unchanged after all operations', sha256(read('source-response.ttl')), source.response.sha256);

const scenario = {
  id:'kaunas-air-quality',
  title:'Kaunas 空气质量开放目录',
  description:'从欧盟官方目录导入立陶宛 Kaunas 空气质量元数据。删除 CSV 访问入口会影响该分发条目与所属数据集；将入口原子替换为源记录已有的 CSV 下载地址后，本地工作副本通过校验。',
  sourceUrl:source.recordUrl,
  sourceLabel:'data.europa.eu · Air quality in Kaunas',
  recordIri:source.datasetIri,
  affectedLabel:'CSV 分发条目及所属数据集',
  distributionIri:distribution.value,
  originalAccessUrl:removed.object.value,
  replacementAccessUrl:added.object.value,
  currentUrl:removed.object.value,
  replacementUrl:added.object.value,
  metadataLicense:source.metadataLicense,
  dataLicense:source.underlyingDataLicense,
  sourceSha256:source.response.sha256,
  sourceTriples:originalGraph.size,
  importedTriples:imported.size,
  distributionCount:distributionIds.length,
  profileLabel:'MoonSHACL 本地目录导入 profile（非完整 DCAT-AP 认证）',
  officialSummary:{conforms:rawOfficial.report.conforms,results:rawOfficial.report.results.length,description:'冻结官方查询切片验收：341 条原始语句 / 26 个 Class 违规。链接资源的类型描述未随查询切片获取；此结果不是对上游完整目录的判定。31 条导入投影单独检验为 20 个 Class 违规。现场交互采用明确的本地导入 profile。'},
  source:{recordUrl:source.recordUrl,originalCatalogueUrl:source.originalCatalogueUrl,responseFile:'examples/real-catalogue/source-response.ttl',queryFile:'examples/real-catalogue/source-query.rq',manifestFile:'examples/real-catalogue/SOURCES.json',retrievedAt:source.retrievedAt,projection:'从 341 条官方查询响应中按白名单筛出 31 条原始语句；只保留英文或无语言标签的文本，未补造任何类型或字段。',profile:'自定义本地目录导入 profile，与官方 DCAT-AP 3.0.0 base 结果分别呈现。'},
  baseline:{rawOfficialConforms:rawOfficial.report.conforms,rawOfficialResults:rawOfficial.report.results.length,projectedOfficialConforms:projectedOfficial.report.conforms,projectedOfficialResults:projectedOfficial.report.results.length,applicationConforms:true,note:'官方 base 的 Class 违规是此查询切片未包含链接资源类型的结果；未补造类型以获取通过，也不能据此认定上游完整目录不合规。'},
  mutationLabel:'人为错误注入：删除 CSV accessURL',
  repairLabel:'本地变更：将 CSV 官方下载链接用作访问入口',
  repairNote:'替换值已存在于原记录的 dcat:downloadURL；这是本地工作副本的访问策略调整，未修改官方快照或写回上游。',
  data, shapes, removals, repairAdditions,
};
const files = {'data.ttl':data,'remove-access-url.ttl':removals,'repair-access-url.ttl':repairAdditions,'scenario.json':JSON.stringify(scenario,null,2)+'\n'};
if (process.argv.includes('--write-fixture')) for (const [filename, value] of Object.entries(files)) fs.writeFileSync(path.join(directory,filename),value);
for (const [filename,value] of Object.entries(files)) check(`${filename} matches the source-derived fixture`, read(filename), value);

const summary = result => ({status:result.status,conforms:result.report?.conforms,results:result.report?.results.length,diagnostics:result.diagnostics ?? [],...(result.committed === undefined ? {} : {committed:result.committed}),work:result.report?.work});
const evidence = {
  schemaVersion:1,
  scope:'One real public metadata record, frozen and projected without invented source statements; local integration demonstration, not external adoption or full DCAT-AP certification.',
  command:'node scripts/real-data.mjs',
  snapshotDate:source.retrievedAt,
  source:{recordUrl:source.recordUrl,endpoint:source.endpoint,datasetIri:source.datasetIri,responseSha256:source.response.sha256,querySha256:source.query.sha256,metadataLicense:source.metadataLicense,underlyingDataLicense:source.underlyingDataLicense},
  engine:{bridge:'dist/moonshacl.mjs',sha256:sha256(fs.readFileSync(path.join(root,'dist/moonshacl.mjs'))),node:process.version},
  checks,passed:checks,failed:0,
  counts:{sourceTriples:originalGraph.size,importedTriples:imported.size,distributions:distributionIds.length,finalTriples:finalGraph.size},
  rawOfficial:{...summary(rawOfficial),profile:source.officialProfile,report:rawOfficial.report},
  projectedOfficial:{...summary(projectedOfficial),note:scenario.baseline.note},
  originalApplication:summary(originalApplication),
  importedApplication:summary(importedApplication),
  deliberatelyBroken:summary(broken),
  rejected:{...summary(rejected),rollbackGraphEqualsOriginal:true,report:rejected.report},
  accepted:{...summary(accepted),changedTriples:{removed:1,added:1},replacementIsPublishedDownloadUrl:true,graphEqualsExpected:true},
  readback:summary(readback),
  sourceUnchanged:true,
  exportFile:'artifacts/real-catalogue/committed.nt',
  outputGraphSha256:sha256(accepted.graphRdf),
};
const evidencePath = path.join(root,process.argv.includes('--record') ? 'docs/evidence/real-data.json' : 'artifacts/real-data.json');
fs.mkdirSync(path.dirname(evidencePath),{recursive:true});
writeJson(evidencePath,evidence);
console.log(`${checks}/${checks} real-data checks passed. ${originalGraph.size} source triples -> ${imported.size} imported triples; ${distributionIds.length} distributions. Official base: ${rawOfficial.report.results.length} raw / ${projectedOfficial.report.results.length} projected results (conforms=false); local profile: import, rollback, replacement and readback passed.`);
console.log(`Evidence: ${path.relative(root,evidencePath).split(path.sep).join('/')}`);
