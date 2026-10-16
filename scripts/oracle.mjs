import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { Parser, Store, Writer } from 'n3';
import { Validator } from 'shacl-engine';
import SHACLValidator from 'rdf-validate-shacl';
import rdf from '@rdfjs/data-model';
import { request } from '../dist/moonshacl.mjs';

const sh = 'http://www.w3.org/ns/shacl#';
const ex = 'https://example.org/';
const base = 'https://example.org/input';
const prefixes = '@prefix ex: <https://example.org/> . @prefix sh: <http://www.w3.org/ns/shacl#> . @prefix xsd: <http://www.w3.org/2001/XMLSchema#> . ';
const read = file => fs.readFileSync(file, 'utf8');
const rdfjsVersion = JSON.parse(read('node_modules/rdf-validate-shacl/package.json')).version;
const secondaryVersion = JSON.parse(read('node_modules/shacl-engine/package.json')).version;
assert.equal(rdfjsVersion, '0.6.5', 'Independent RDF/JS engine must match its pinned version');
const parse = (text, baseIRI = base) => new Store(new Parser({ baseIRI }).parse(text));
const write = dataset => new Promise((resolve, reject) => {
  const writer = new Writer({ format: 'N-Triples' });
  writer.addQuads([...dataset]);
  writer.end((error, text) => error ? reject(error) : resolve(text));
});
const jsonTerm = term => term ? {
  termType: term.termType, value: term.value,
  ...(term.termType === 'Literal' ? { datatype: term.datatype.value, language: term.language || null } : {}),
} : null;
const named = value => ({ termType: 'NamedNode', value });
const lit = (value, datatype) => ({ termType: 'Literal', value, datatype: 'http://www.w3.org/2001/XMLSchema#' + datatype, language: null });
const shapesFile = read('examples/people-shapes.ttl');
const dataFile = read('examples/people-data.ttl');
const cases = [
  ['people-valid', shapesFile, dataFile],
  ['shared-name-missing', shapesFile, dataFile.replace('ex:acme ex:name "Acme" .', '')],
  ['inverse-count', prefixes + 'ex:S a sh:PropertyShape; sh:targetNode ex:company; sh:path [sh:inversePath ex:employer]; sh:minCount 2 .', prefixes + 'ex:alice ex:employer ex:company .'],
  ['node-datatype', prefixes + 'ex:S a sh:NodeShape; sh:targetNode "invalid"; sh:datatype xsd:integer .', ''],
  ['language-unique', prefixes + 'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path ex:p; sh:uniqueLang true .', prefixes + 'ex:s ex:p "one"@en, "two"@EN .'],
  ['closed', prefixes + 'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:closed true; sh:property [sh:path ex:p] .', prefixes + 'ex:s ex:p "ok"; ex:q "bad" .'],
  ['qualified', prefixes + 'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path ex:p; sh:qualifiedValueShape [sh:datatype xsd:string]; sh:qualifiedMinCount 2 .', prefixes + 'ex:s ex:p "one", 7 .'],
  ['logic', prefixes + 'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:xone ([sh:nodeKind sh:IRI] [sh:nodeKind sh:BlankNodeOrIRI]) .', ''],
  ['alternative-path', prefixes + 'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path [sh:alternativePath (ex:p ex:q)]; sh:minCount 2 .', prefixes + 'ex:s ex:p "one"; ex:q "one" .'],
  ['class-closure', prefixes + 'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:class ex:Parent .', prefixes + 'ex:s a ex:Child . ex:Child <http://www.w3.org/2000/01/rdf-schema#subClassOf> ex:Parent .'],
  ['qualified-sibling-without-count', prefixes + 'ex:S sh:targetNode ex:root; sh:property ex:P, ex:Q . ex:P sh:path ex:member; sh:qualifiedValueShape ex:A; sh:qualifiedMinCount 1; sh:qualifiedValueShapesDisjoint true . ex:Q sh:path ex:other; sh:qualifiedValueShape ex:B . ex:A sh:class ex:TypeA . ex:B sh:class ex:TypeB .', prefixes + 'ex:root ex:member ex:item . ex:item a ex:TypeA, ex:TypeB .'],
  ['signed-integer', prefixes + 'ex:S sh:targetNode "+01"^^xsd:integer; sh:datatype xsd:integer .', ''],
  ['dcat-valid', read('fixtures/dcat-ap-3.0.0.ttl'), read('examples/dcat-data.ttl')],
  ['dcat-access-url-missing', read('fixtures/dcat-ap-3.0.0.ttl'), read('examples/dcat-data.ttl').replace('a dcat:Distribution;\n  dcat:accessURL <https://example.org/data.csv> .', 'a dcat:Distribution .')],
].map(([name, shapes, data]) => ({ name, shapes, data, group: 'original-regressions', shapesBase: base, dataBase: base }));

const expected = (conforms, ...components) => ({ conforms, results: components.length, components: components.sort() });
const originalExpectations = [
  expected(true), expected(false, 'MinCountConstraintComponent', 'MinCountConstraintComponent'),
  expected(false, 'MinCountConstraintComponent'), expected(false, 'DatatypeConstraintComponent'),
  expected(false, 'UniqueLangConstraintComponent'), expected(false, 'ClosedConstraintComponent'),
  expected(false, 'QualifiedMinCountConstraintComponent'), expected(false, 'XoneConstraintComponent'),
  expected(false, 'MinCountConstraintComponent'), expected(true),
  expected(false, 'QualifiedMinCountConstraintComponent'), expected(true), expected(true),
  expected(false, 'MinCountConstraintComponent'),
];
for (const [index, item] of cases.entries()) item.expected = originalExpectations[index];
const siblingCase = cases.find(c => c.name === 'qualified-sibling-without-count');
siblingCase.expected = expected(false, 'QualifiedMinCountConstraintComponent');
siblingCase.knownErrors = { pySHACL: {
  type: 'ConstraintLoadError', includes: 'QualifiedValueShapeConstraintComponent must have at lease one sh:qualifiedMinCount or sh:qualifiedMaxCount',
  reason: 'The pinned pySHACL rejects the count-free sibling shape, while SHACL instantiates a component only when all mandatory parameters are present. The raw qualifiedValueShape still participates in sibling exclusion.',
  specification: 'https://www.w3.org/TR/2017/REC-shacl-20170720/#constraint-components',
} };
const acceptance = JSON.parse(read('examples/core-roadmap/expectations.json'));
for (const entry of acceptance.cases) {
  cases.push({
    name: 'core-' + entry.id, group: 'seven-new-components',
    shapes: read('examples/core-roadmap/' + entry.shapes), data: read('examples/core-roadmap/' + entry.data),
    shapesBase: base, dataBase: base,
    expected: expected(entry.expected.conforms, ...entry.expected.violations.map(v => v.sourceConstraintComponent.replace(sh, ''))),
  });
}

const add = (name, constraint, data, expectation, extra = {}) => cases.push({
  name, group: 'semantic-boundaries', shapes: prefixes + 'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path ex:p; ' + constraint + ' .',
  data: prefixes + data, shapesBase: base, dataBase: base, expected: expectation, ...extra,
});
const wrongRangeReport = (component, value, datatype) => ({ conforms: false, results: [{
  focusNode: named(ex + 's'), sourceShape: named(ex + 'S'), sourceConstraintComponent: sh + component,
  resultSeverity: named(sh + 'Violation'), value: lit(value, datatype), resultPath: { predicate: ex + 'p' },
}] });
const precisionDivergence = (value, datatype) => ({ 'rdf-validate-shacl': {
  reason: 'The pinned RDF/JS validator compares these values through binary64 Number, losing the exact integer/decimal distinction. The product expectation is independently fixed from the exact ordered values.',
  specification: 'https://www.w3.org/TR/sparql11-query/#OperatorMapping',
  report: wrongRangeReport('MinExclusiveConstraintComponent', value, datatype),
} });
add('integer-above-binary64-precision', 'sh:minExclusive 9007199254740992', 'ex:s ex:p 9007199254740993 .', expected(true), {
  knownDivergences: precisionDivergence('9007199254740993', 'integer'),
});
add('decimal-exact-order', 'sh:minExclusive "0.1000000000000000000000000000000001"^^xsd:decimal', 'ex:s ex:p "0.1000000000000000000000000000000002"^^xsd:decimal .', expected(true), {
  knownDivergences: precisionDivergence('0.1000000000000000000000000000000002', 'decimal'),
});
add('numeric-type-promotion', 'sh:minInclusive 1.5', 'ex:s ex:p "2"^^xsd:int .', expected(true));
add('float-nan-range', 'sh:minInclusive 0', 'ex:s ex:p "NaN"^^xsd:double .', expected(false, 'MinInclusiveConstraintComponent'));
add('float-infinity', 'sh:minExclusive 1', 'ex:s ex:p "INF"^^xsd:double .', expected(true), { knownDivergences: { 'rdf-validate-shacl': {
  reason: 'The pinned RDF/JS numeric comparison does not recognize the valid XSD INF lexical form. Positive infinity is greater than finite 1.',
  specification: 'https://www.w3.org/TR/sparql11-query/#OperatorMapping',
  report: wrongRangeReport('MinExclusiveConstraintComponent', 'INF', 'double'),
} } });
add('float-invalid-lexical', 'sh:datatype xsd:float', 'ex:s ex:p "not-a-float"^^xsd:float .', expected(false, 'DatatypeConstraintComponent'));
add('dateTime-offset-equality', 'sh:lessThan ex:end', 'ex:s ex:p "2026-10-16T10:00:00+02:00"^^xsd:dateTime; ex:end "2026-10-16T08:00:00Z"^^xsd:dateTime .', expected(false, 'LessThanConstraintComponent'));
add('incomparable-property-values', 'sh:lessThan ex:end', 'ex:s ex:p "bad"; ex:end 5 .', expected(false, 'LessThanConstraintComponent'));
add('comparison-pair-multiplicity', 'sh:lessThan ex:end', 'ex:s ex:p 5, 6; ex:end 3, 4 .', expected(false, ...Array(4).fill('LessThanConstraintComponent')));
add('custom-datatype-iri-match', 'sh:datatype ex:opaque', 'ex:s ex:p "opaque lexical value"^^ex:opaque .', expected(true));
add('huge-cardinality-threshold', 'sh:maxCount 184467440737095516160000', '', expected(true));
add('regex-multiline', 'sh:pattern "^b$"; sh:flags "m"', 'ex:s ex:p "a\\nb\\nc" .', expected(true));
add('regex-dot-all', 'sh:pattern "^a.*c$"; sh:flags "s"', 'ex:s ex:p "a\\nb\\nc" .', expected(true), { knownDivergences: { pySHACL: {
  reason: 'pySHACL 0.30.1 PatternConstraintComponent.__init__ maps only i and m flags; it ignores the XPath s flag. MoonSHACL and the RDF/JS oracle match across newlines.',
  specification: 'https://www.w3.org/TR/2010/REC-xpath-functions-20101214/#flags',
  report: wrongRangeReport('PatternConstraintComponent', 'a\nb\nc', 'string'),
} } });
add('regex-backreference', 'sh:pattern "^(ab)\\\\1$"', 'ex:s ex:p "abab" .', expected(true));
add('language-range-case-insensitive', 'sh:languageIn ("EN")', 'ex:s ex:p "one"@en, "two"@EN-us .', expected(true), {
  knownDivergences: { 'rdf-validate-shacl': {
    reason: 'The pinned RDF/JS validator compares a language range case-sensitively. SPARQL langMatches applies case-insensitive basic language-range filtering.',
    specification: 'https://www.w3.org/TR/sparql11-query/#func-langMatches',
    report: { conforms: false, results: [['one', 'en'], ['two', 'en-us']].map(([value, language]) => ({
      focusNode: named(ex + 's'), sourceShape: named(ex + 'S'), sourceConstraintComponent: sh + 'LanguageInConstraintComponent',
      resultSeverity: named(sh + 'Violation'), resultPath: { predicate: ex + 'p' },
      value: { termType: 'Literal', value, language, datatype: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#langString' },
    })) },
  } },
});
const nodeReport = component => ({ conforms: false, results: [{
  focusNode: named(ex + 's'), sourceShape: named(ex + 'S'), sourceConstraintComponent: sh + component,
  resultSeverity: named(sh + 'Violation'), value: named(ex + 's'),
}] });
cases.push(
  { name: 'implicit-class-requires-shape-instance', group: 'semantic-boundaries',
    shapes: prefixes + 'ex:S a <http://www.w3.org/2000/01/rdf-schema#Class>; sh:class ex:C .',
    data: prefixes + 'ex:s a ex:S .', expected: expected(true),
    knownDivergences: { 'rdf-validate-shacl': {
      reason: 'A constraint makes ex:S a shape, but implicit class targets additionally require a SHACL instance of sh:NodeShape or sh:PropertyShape. The RDF/JS validator omits that second condition.',
      specification: 'https://www.w3.org/TR/2017/REC-shacl-20170720/#ImplicitClassTarget',
      report: nodeReport('ClassConstraintComponent'),
    } },
  },
  { name: 'node-multiple-equals-constraints', group: 'semantic-boundaries',
    shapes: prefixes + 'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:equals ex:p, ex:q .',
    data: '', expected: expected(false, 'EqualsConstraintComponent', 'EqualsConstraintComponent'),
  },
);
cases.push(
  { name: 'distinct-anonymous-source-shapes', group: 'blank-node-identity', shapes: prefixes + 'ex:S sh:targetNode ex:s; sh:property [sh:path ex:p; sh:minCount 1], [sh:path ex:q; sh:minCount 2] .', data: '', expected: expected(false, 'MinCountConstraintComponent', 'MinCountConstraintComponent') },
  { name: 'shared-anonymous-source-multiplicity', group: 'blank-node-identity', shapes: prefixes + 'ex:A sh:targetNode ex:s; sh:property _:p . ex:B sh:targetNode ex:s; sh:property _:p . _:p sh:path ex:p; sh:minCount 1 .', data: '', expected: expected(false, 'MinCountConstraintComponent', 'MinCountConstraintComponent') },
  { name: 'anonymous-focus-and-value', group: 'blank-node-identity', shapes: prefixes + 'ex:S sh:targetSubjectsOf ex:p; sh:property [sh:path ex:p; sh:datatype xsd:string] .', data: prefixes + '_:subject ex:p _:value .', expected: expected(false, 'DatatypeConstraintComponent') },
);

// Read the complete fixed W3C collection from its checked-in embedded strings.
if (!process.argv.includes('--focused')) {
  const embedded = read('src/conformance/fixtures_wbtest.mbt');
  const section = embedded.slice(embedded.indexOf('fn official_resources'));
  const tuple = /\(\s*("(?:\\.|[^"\\])*")\s*,\s*\[([\s\S]*?)\]\s*\.join\(""\)\s*,?\s*\)/g;
  const resources = new Map();
  for (const match of section.matchAll(tuple)) {
    const chunks = [...match[2].matchAll(/"(?:\\.|[^"\\])*"/g)].map(m => JSON.parse(m[0]));
    resources.set(JSON.parse(match[1]), chunks.join(''));
  }
  const sources = JSON.parse(read('fixtures/SOURCES.json'));
  assert.equal(resources.size, sources.allEmbeddedResources.length, 'All fixed W3C resources must be extracted');
  const mf = 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#';
  const sht = 'http://www.w3.org/ns/shacl-test#';
  for (const { name } of sources.validationFiles) {
    const iri = 'http://datashapes.org/sh/tests/core/' + name;
    const manifest = parse(resources.get(iri), iri);
    const test = rdf.namedNode(iri.replace(/\.ttl$/, ''));
    const action = [...manifest.match(test, rdf.namedNode(mf + 'action'), null)][0].object;
    const graph = kind => [...manifest.match(action, rdf.namedNode(sht + kind), null)][0].object.value;
    const shapesBase = graph('shapesGraph'), dataBase = graph('dataGraph');
    assert(resources.has(shapesBase) && resources.has(dataBase), name + ': missing fixed graph');
    const report = [...manifest.match(test, rdf.namedNode(mf + 'result'), null)][0].object;
    const conforms = [...manifest.match(report, rdf.namedNode(sh + 'conforms'), null)][0].object.value === 'true';
    const components = [...manifest.match(report, rdf.namedNode(sh + 'result'), null)].map(q =>
      [...manifest.match(q.object, rdf.namedNode(sh + 'sourceConstraintComponent'), null)][0].object.value.replace(sh, ''));
    const item = { name: 'w3c/' + name, group: 'official-core', shapes: resources.get(shapesBase), data: resources.get(dataBase), shapesBase, dataBase,
      expected: expected(conforms, ...components) };
    if (name === 'property/uniqueLang-002.ttl') {
      const iri = 'http://example.org/shacl-test/';
      item.knownDivergences = { pySHACL: {
        reason: 'The official uniqueLang-002 fixture requires RDF-term true, not the distinct "1"^^xsd:boolean literal. pySHACL coerces "1" to Python True and activates the constraint.',
        specification: 'https://www.w3.org/TR/2017/REC-shacl-20170720/#UniqueLangConstraintComponent',
        report: { conforms: false, results: [{ focusNode: named(iri + 'i'), sourceShape: named(iri + 's1'),
          sourceConstraintComponent: sh + 'UniqueLangConstraintComponent', resultSeverity: named(sh + 'Violation'),
          resultPath: { predicate: iri + 'message' } }] },
      } };
    }
    cases.push(item);
  }
}

const bundledPython = process.platform === 'win32' ? path.join(process.env.USERPROFILE || '', '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe') : '';
const python = process.env.MOONSHACL_PYTHON || process.env.PYTHON || (bundledPython && fs.existsSync(bundledPython) ? bundledPython : process.platform === 'win32' ? 'python' : 'python3');
const localDeps = path.resolve('.tools/pyshacl');
const env = { ...process.env, PYTHONUTF8: '1' };
if (fs.existsSync(localDeps)) env.PYTHONPATH = [localDeps, process.env.PYTHONPATH].filter(Boolean).join(path.delimiter);
const pythonOptions = { encoding: 'utf8', env, maxBuffer: 64 * 1024 * 1024 };
const pythonFailure = (stage, result) => new Error([
  `Independent Python oracle ${stage} failed.`,
  `Interpreter: ${python}`,
  `Exit status: ${result.status}; signal: ${result.signal}; spawn error: ${result.error?.message || 'none'}`,
  'Install requirements-oracle.txt for this interpreter and ensure the dependency files are readable in the current execution context. MOONSHACL_PYTHON selects another interpreter.',
  result.stderr?.trim() ? `Python stderr:\n${result.stderr.trim().slice(-12000)}` : 'Python stderr: <empty>',
  result.stdout?.trim() ? `Python stdout:\n${result.stdout.trim().slice(-3000)}` : 'Python stdout: <empty>',
].join('\n'), result.error ? { cause: result.error } : undefined);
// Detect missing/inaccessible packages before generating the large input. An
// early Python import failure otherwise closes its pipe while Node is writing.
const preflight = spawnSync(python, ['scripts/pyshacl-oracle.py', '--check'], pythonOptions);
if (preflight.error || preflight.status !== 0) throw pythonFailure('dependency preflight', preflight);

const payload = [];
for (const item of cases) {
  item.shapesBase ??= base;
  item.dataBase ??= base;
  const input = { shapes: item.shapes, data: item.data, shapesBase: item.shapesBase, dataBase: item.dataBase };
  const actual = JSON.parse(request(JSON.stringify(input)));
  assert.equal(actual.status, 'validated', `${item.name}: ${JSON.stringify(actual)}`);
  const audit = JSON.parse(request(JSON.stringify({ ...input, operation: 'audit' })));
  assert.equal(audit.status, 'supported', item.name + ': audit');
  assert.equal(typeof audit.dataRdf, 'string', 'Audit must expose the same parsed data blank nodes');
  const shapes = parse(item.shapes, item.shapesBase), data = parse(item.data, item.dataBase);
  const oracle = await new SHACLValidator(shapes).validate(data);
  payload.push({ ...item, actual, moonShapesRdf: audit.shapesRdf, moonDataRdf: audit.dataRdf,
    rdfjsShapesRdf: await write(shapes), rdfjsDataRdf: await write(data),
    rdfjsReportRdf: await write(oracle.dataset), rdfjsReportRoot: jsonTerm(oracle.term),
  });
}
// A file descriptor avoids Windows pipe EOF/EPIPE obscuring a child's early
// diagnostic, and bounds memory used by the transport. The file is always removed.
const inputDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'moonshacl-oracle-'));
const inputFile = path.join(inputDirectory, 'cases.json');
let inputDescriptor, processResult;
try {
  fs.writeFileSync(inputFile, JSON.stringify({ cases: payload }));
  inputDescriptor = fs.openSync(inputFile, 'r');
  processResult = spawnSync(python, ['scripts/pyshacl-oracle.py'], {
    ...pythonOptions, stdio: [inputDescriptor, 'pipe', 'pipe'],
  });
} finally {
  if (inputDescriptor !== undefined) fs.closeSync(inputDescriptor);
  if (fs.existsSync(inputFile)) fs.unlinkSync(inputFile);
  fs.rmdirSync(inputDirectory);
}
if (processResult.error) throw pythonFailure('execution', processResult);
let result;
try { result = JSON.parse(processResult.stdout); }
catch { throw pythonFailure('JSON response', processResult); }
const factory = Object.assign(Object.create(rdf), { dataset: quads => new Store(quads) });
const secondary = await new Validator(parse(prefixes + 'ex:S a sh:NodeShape; sh:targetNode "invalid"; sh:datatype xsd:integer .'), { factory }).validate({ dataset: parse('') });
const rows = result.cases.map(row => ({ ...row, conforms: row.product.conforms, results: row.product.results,
  status: row.comparisons.every(c => c.status === 'matched') ? 'matched' : 'documented-engine-divergence' }));
const evidence = {
  engines: [{ name: 'rdf-validate-shacl', version: rdfjsVersion }, { name: 'pySHACL', version: result.versions.pyshacl, rdflib: result.versions.rdflib }],
  comparison: 'RDF graph isomorphism over input graphs plus projected result graphs, preserving anonymous sourceShape/focus/value identity and distinct result multiplicity; paths compared structurally.',
  comparedFields: ['conforms', 'focusNode', 'sourceShape (input-linked blank-node isomorphism)', 'sourceConstraintComponent', 'resultSeverity', 'value', 'resultPath (structural)'],
  optionalFields: 'Engine-generated resultMessage and detail excluded; official fixture tests separately check required messages.',
  projectionSelfTests: result.projectionSelfTests, totalCases: cases.length,
  comparisonCounts: {
    total: rows.reduce((n, row) => n + row.comparisons.length, 0),
    matched: rows.flatMap(row => row.comparisons).filter(row => row.status === 'matched').length,
    documentedEngineDivergences: rows.flatMap(row => row.comparisons).filter(row => row.status === 'documented-engine-divergence').length,
    documentedEngineErrors: rows.flatMap(row => row.comparisons).filter(row => row.status === 'documented-engine-error').length,
    unexpectedFailures: result.failures.length,
  },
  cases: rows, failures: result.failures,
  secondaryObservations: [{ engine: 'shacl-engine', version: secondaryVersion, case: 'explicit literal target, empty data graph', conforms: secondary.conforms,
    note: 'ShapeValidator.js skips validation when dataset.size === 0; both primary independent oracles validate the explicit target.' }],
};
fs.mkdirSync('audit/2026-10-10', { recursive: true });
fs.writeFileSync('audit/2026-10-10/oracle.json', JSON.stringify(evidence, null, 2) + '\n');
if (processResult.status !== 0 || result.failures.length) {
  throw new Error('Independent oracle comparison failed:\n' + JSON.stringify(result.failures, null, 2));
}
const divergences = rows.flatMap(r => r.comparisons).filter(r => r.status !== 'matched').length;
console.log(`${rows.length}/${cases.length} cases verified against two independent engines; ${divergences} explicitly checked engine divergences; ${result.projectionSelfTests} comparison-harness self-tests.`);
