import fs from 'node:fs';
import assert from 'node:assert/strict';
import { Parser, Store } from 'n3';
import { Validator } from 'shacl-engine';
import SHACLValidator from 'rdf-validate-shacl';
import rdf from '@rdfjs/data-model';
import { request } from '../dist/moonshacl.mjs';
const factory = Object.assign(Object.create(rdf), { dataset: quads => new Store(quads) });
const sh = 'http://www.w3.org/ns/shacl#';
const rows = [];
const parse = text => new Store(new Parser({baseIRI:'https://example.org/input'}).parse(text));
const prefixes = '@prefix ex: <https://example.org/> . @prefix sh: <http://www.w3.org/ns/shacl#> . @prefix xsd: <http://www.w3.org/2001/XMLSchema#> . ';
const shapesFile = fs.readFileSync('examples/people-shapes.ttl','utf8');
const dataFile = fs.readFileSync('examples/people-data.ttl','utf8');
const cases = [
  ['people-valid',shapesFile,dataFile],
  ['shared-name-missing',shapesFile,dataFile.replace('ex:acme ex:name "Acme" .','')],
  ['inverse-count',prefixes+'ex:S a sh:PropertyShape; sh:targetNode ex:company; sh:path [sh:inversePath ex:employer]; sh:minCount 2 .',prefixes+'ex:alice ex:employer ex:company .'],
  ['node-datatype',prefixes+'ex:S a sh:NodeShape; sh:targetNode "invalid"; sh:datatype xsd:integer .',''],
  ['language-unique',prefixes+'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path ex:p; sh:uniqueLang true .',prefixes+'ex:s ex:p "one"@en, "two"@EN .'],
  ['closed',prefixes+'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:closed true; sh:property [sh:path ex:p] .',prefixes+'ex:s ex:p "ok"; ex:q "bad" .'],
  ['qualified',prefixes+'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path ex:p; sh:qualifiedValueShape [sh:datatype xsd:string]; sh:qualifiedMinCount 2 .',prefixes+'ex:s ex:p "one", 7 .'],
  ['logic',prefixes+'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:xone ([sh:nodeKind sh:IRI] [sh:nodeKind sh:BlankNodeOrIRI]) .',''],
  ['alternative-path',prefixes+'ex:S a sh:PropertyShape; sh:targetNode ex:s; sh:path [sh:alternativePath (ex:p ex:q)]; sh:minCount 2 .',prefixes+'ex:s ex:p "one"; ex:q "one" .'],
  ['class-closure',prefixes+'ex:S a sh:NodeShape; sh:targetNode ex:s; sh:class ex:Parent .',prefixes+'ex:s a ex:Child . ex:Child <http://www.w3.org/2000/01/rdf-schema#subClassOf> ex:Parent .'],
  ['qualified-sibling-without-count',prefixes+'ex:S sh:targetNode ex:root; sh:property ex:P, ex:Q . ex:P sh:path ex:member; sh:qualifiedValueShape ex:A; sh:qualifiedMinCount 1; sh:qualifiedValueShapesDisjoint true . ex:Q sh:path ex:other; sh:qualifiedValueShape ex:B . ex:A sh:class ex:TypeA . ex:B sh:class ex:TypeB .',prefixes+'ex:root ex:member ex:item . ex:item a ex:TypeA, ex:TypeB .'],
  ['signed-integer',prefixes+'ex:S sh:targetNode "+01"^^xsd:integer; sh:datatype xsd:integer .',''],
  ['dcat-valid',fs.readFileSync('fixtures/dcat-ap-3.0.0.ttl','utf8'),fs.readFileSync('examples/dcat-data.ttl','utf8')],
  ['dcat-access-url-missing',fs.readFileSync('fixtures/dcat-ap-3.0.0.ttl','utf8'),fs.readFileSync('examples/dcat-data.ttl','utf8').replace('a dcat:Distribution;\n  dcat:accessURL <https://example.org/data.csv> .','a dcat:Distribution .')],
];
const term = t => t ? `${t.termType}:${t.value}${t.termType==='Literal'?`^^${t.datatype.value}@${t.language.toLowerCase()}`:''}` : '';
const moonTerm = t => t ? `${t.termType}:${t.value}${t.termType==='Literal'?`^^${t.datatype}@${(t.language||'').toLowerCase()}`:''}` : '';
function pathJson(dataset,node) {
  if (!node) return null;
  if (node.termType==='NamedNode') return {predicate:node.value};
  const get = p => [...dataset.match(node,rdf.namedNode(p),null)][0]?.object;
  const list = head => {
    const items=[],seen=new Set();
    while (head.value!=='http://www.w3.org/1999/02/22-rdf-syntax-ns#nil') {
      assert(!seen.has(head.value),'Cyclic report path');seen.add(head.value);
      items.push(pathJson(dataset,[...dataset.match(head,rdf.namedNode('http://www.w3.org/1999/02/22-rdf-syntax-ns#first'),null)][0].object));
      head=[...dataset.match(head,rdf.namedNode('http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'),null)][0].object;
    }
    return items;
  };
  for (const [predicate,key] of [['inversePath','inverse'],['zeroOrMorePath','zeroOrMore'],['oneOrMorePath','oneOrMore'],['zeroOrOnePath','zeroOrOne']]) {
    const child=get(sh+predicate);if(child) return {[key]:pathJson(dataset,child)};
  }
  const alternative=get(sh+'alternativePath');
  return alternative?{alternative:list(alternative)}:{sequence:list(node)};
}
const shapeIdentity = t => t?.termType==='BlankNode'?'BlankNode':term(t);
const moonShapeIdentity = t => t?.termType==='BlankNode'?'BlankNode':moonTerm(t);
for (const [name,shapesText,dataText] of cases) {
  const actual = JSON.parse(request(JSON.stringify({shapes:shapesText,data:dataText})));
  assert.equal(actual.status,'validated',`${name}: ${JSON.stringify(actual)}`);
  const shapes = parse(shapesText), dataset=parse(dataText);
  const oracle = await new SHACLValidator(shapes).validate(dataset);
  const nodes = [...oracle.dataset.match(null,rdf.namedNode(sh+'result'),null)].map(q=>q.object);
  const signatures = nodes.map(n=> {
    const get = p => [...oracle.dataset.match(n,rdf.namedNode(sh+p),null)][0]?.object;
    return [term(get('focusNode')),shapeIdentity(get('sourceShape')),term(get('sourceConstraintComponent')),term(get('resultSeverity')),term(get('value')),JSON.stringify(pathJson(oracle.dataset,get('resultPath')))].join('|');
  }).sort();
  const own = actual.report.results.map(r=>[moonTerm(r.focusNode),moonShapeIdentity(r.sourceShape),`NamedNode:${r.sourceConstraintComponent}`,moonTerm(r.resultSeverity),moonTerm(r.value),JSON.stringify(r.resultPath)].join('|')).sort();
  const ownRdf = new Store(new Parser({format:'N-Triples'}).parse(actual.reportRdf));
  assert.equal([...ownRdf.match(null,rdf.namedNode(sh+'result'),null)].length,actual.report.results.length,`${name}: RDF report result count`);
  assert.equal(actual.report.conforms,oracle.conforms,name);
  assert.deepEqual(own,signatures,name);
  rows.push({name,conforms:actual.report.conforms,results:own.length,status:'matched'});
}
const emptyShape = parse(prefixes+'ex:S a sh:NodeShape; sh:targetNode "invalid"; sh:datatype xsd:integer .');
const secondary = await new Validator(emptyShape,{factory}).validate({dataset:parse('')});
fs.writeFileSync('audit/2026-10-10/oracle.json',JSON.stringify({engine:'rdf-validate-shacl',version:'0.6.5',comparedFields:['conforms','focusNode','sourceShape (IRI exact, blank-node kind only)','sourceConstraintComponent','resultSeverity','value','resultPath (structural)'],cases:rows,secondaryObservations:[{engine:'shacl-engine',version:'1.1.0',case:'explicit literal target, empty data graph',conforms:secondary.conforms,note:'ShapeValidator.js skips all validation when dataset.size === 0. MoonSHACL follows the explicit target and reports a datatype violation; primary oracle agrees.'}]},null,2));
console.log(`${rows.length}/${rows.length} independent engine comparisons matched.`);
