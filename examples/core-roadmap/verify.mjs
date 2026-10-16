import fs from 'node:fs';
import assert from 'node:assert/strict';
import { Parser, Store } from 'n3';
import SHACLValidator from 'rdf-validate-shacl';
import rdf from '@rdfjs/data-model';

const base = new URL('./', import.meta.url);
const manifest = JSON.parse(fs.readFileSync(new URL('expectations.json', base), 'utf8'));
const checkCurrentProfile = process.argv.includes('--check-current-profile');
const requireCore = process.argv.includes('--require-core');
assert(!(checkCurrentProfile && requireCore), 'Choose a historical baseline check or Core acceptance, not both');
assert(process.argv.slice(2).every(arg=>['--check-current-profile','--require-core'].includes(arg)), 'Unknown verification option');
const request = checkCurrentProfile || requireCore
  ? (await import('../../dist/moonshacl.mjs')).request
  : null;
const sh = 'http://www.w3.org/ns/shacl#';
const parse = text => new Store(new Parser().parse(text));
const signature = value => [
  value.sourceConstraintComponent, value.focusNode,
  value.resultPath, value.sourceShape,
].join('|');
const rows = [];

for (const item of manifest.cases) {
  const shapes = fs.readFileSync(new URL(item.shapes, base), 'utf8');
  const data = fs.readFileSync(new URL(item.data, base), 'utf8');
  const result = await new SHACLValidator(parse(shapes)).validate(parse(data));
  const nodes = [...result.dataset.match(null, rdf.namedNode(sh + 'result'), null)]
    .map(quad => quad.object);
  const violations = nodes.map(node => {
    const value = predicate => [...result.dataset.match(
      node, rdf.namedNode(sh + predicate), null,
    )][0]?.object.value;
    return {
      sourceConstraintComponent: value('sourceConstraintComponent'),
      focusNode: value('focusNode'),
      resultPath: value('resultPath'),
      sourceShape: value('sourceShape'),
    };
  });
  assert.equal(result.conforms, item.expected.conforms, item.id + ': conforms');
  assert.deepEqual(
    violations.map(signature).sort(),
    item.expected.violations.map(signature).sort(),
    item.id + ': report fields',
  );
  const row = { id: item.id, conforms: result.conforms, violations: violations.length };
  if (request) {
    const current = JSON.parse(request(JSON.stringify({ shapes, data })));
    if (checkCurrentProfile) {
      assert.equal(current.status, manifest.historicalMoonSHACL.expectedStatusForEveryCase, item.id + ': current profile rejection');
      assert.equal(current.report, undefined, item.id + ': rejection must not fabricate a validation report');
    } else {
      assert.equal(current.status, 'validated', item.id + ': Core feature has not been implemented');
      assert.equal(current.report.conforms, item.expected.conforms, item.id + ': MoonSHACL conforms');
      const actual=current.report.results.map(r=>({sourceConstraintComponent:r.sourceConstraintComponent,focusNode:r.focusNode.value,resultPath:r.resultPath?.predicate,sourceShape:r.sourceShape.value}));
      assert.deepEqual(actual.map(signature).sort(), item.expected.violations.map(signature).sort(), item.id + ': MoonSHACL report fields');
    }
    row.currentStatus = current.status;
  }
  rows.push(row);
}

console.log(JSON.stringify({
  oracle: 'rdf-validate-shacl@0.6.5',
  matchedCases: rows.length,
  checkCurrentProfile,
  requireCore,
  note: requireCore ? 'MoonSHACL matched these ten examples; broader Core gates still apply.' : 'Oracle-only run; use --require-core to verify MoonSHACL execution.',
  rows,
}, null, 2));
