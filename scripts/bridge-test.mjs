import assert from 'node:assert/strict';
import fs from 'node:fs';
import {request} from '../dist/moonshacl.mjs';
const run = value => JSON.parse(request(JSON.stringify(value)));
for (const value of [null,[],0,{}, {data:''},{shapes:''},{shapes:3,data:''},{shapes:'',data:null},{shapes:'',data:'',operation:3},{shapes:'',data:'',operation:'unknown'},{shapes:'',data:'',operation:'update'}]) {
  assert.equal(run(value).status,'request-error',JSON.stringify(value));
}
assert.equal(JSON.parse(request('{invalid')).status,'request-error');
assert.equal(run({shapes:'',data:''}).report.conforms,true);
assert.equal(run({shapes:'<urn:S> <http://www.w3.org/ns/shacl#targetNode> <urn:x>; <http://www.w3.org/ns/shacl#nodeKind> <http://www.w3.org/ns/shacl#Literal> .',data:''}).report.conforms,false);
assert.equal(run({shapes:'@broken',data:''}).status,'parse-error');
assert.equal(run({shapes:fs.readFileSync('examples/people-shapes.ttl','utf8'),data:'@broken'}).status,'parse-error');
assert.equal(run({operation:'update',shapes:'',data:'',additions:'_:x <urn:p> "value" .',removals:''}).status,'request-error');
let checks=17;
const sh='http://www.w3.org/ns/shacl#', owl='http://www.w3.org/2002/07/owl#';
const shapes=`<urn:root> <${owl}imports> <urn:a> .`;
const resources={
  'urn:a':`<urn:a> <${owl}imports> <urn:b> . _:s <${sh}targetNode> <urn:item>; <${sh}nodeKind> <${sh}IRI> .`,
  'urn:b':`<urn:b> <${owl}imports> <urn:a> . _:s <${sh}targetNode> <urn:item>; <${sh}nodeKind> <${sh}Literal> .`,
};
const check=(actual,expected)=>{ assert.deepEqual(actual,expected); checks++; };
check(run({shapes:'',data:'',strict:'yes'}).status,'request-error');
check(run({shapes:'',data:'',resources:[]}).status,'request-error');
check(run({shapes:'',data:'',resources:{'urn:a':2}}).status,'request-error');
check(run({shapes,data:''}).status,'resource-error');
check(run({shapes,data:'',resources:{'urn:a':resources['urn:a']}}).status,'resource-error');
const imported=run({shapes,data:'',resources});
check(imported.status,'validated');check(imported.report.results.length,1);
const linked=run({shapes:'',data:`<urn:data> <${sh}shapesGraph> <urn:a> .`,resources});
check(linked.status,'validated');check(linked.report.results.length,1);
const extension=fs.readFileSync('examples/unsupported-shapes.ttl','utf8');
check(run({shapes:extension,data:''}).diagnostics.length>0,true);
check(run({shapes:extension,data:'',strict:true}).status,'unsupported-or-invalid-shapes');
check(run({shapes:`<urn:o> <${sh}entailment> <urn:unknown> .`,data:''}).status,'unsupported-or-invalid-shapes');
check(run({shapes:`<urn:S> <${sh}targetNode> ""; <${sh}pattern> "(){2147483647}" .`,data:''}).status,'validation-failure');
const dateShapes=`@prefix xsd: <http://www.w3.org/2001/XMLSchema#> . <urn:S> <${sh}targetNode> "2002-10-10T12:00:00-05:00"^^xsd:dateTime; <${sh}minInclusive> "2002-10-10T12:00:00"^^xsd:dateTime .`;
check(run({shapes:dateShapes,data:''}).report.conforms,false);
check(run({shapes:dateShapes,data:'',implicitTimezoneMinutes:0}).report.conforms,true);
check(run({shapes:dateShapes,data:'',implicitTimezoneMinutes:900}).status,'request-error');
check(run({shapes:dateShapes,data:'',implicitTimezoneMinutes:0.5}).status,'request-error');
const rootText=`<urn:root> <${owl}imports> <urn:child> . <urn:S> <${sh}targetNode> <urn:x>; <${sh}property> [<${sh}path> <urn:p>; <${sh}minCount> 1] .`;
const rootCycle={shapes:rootText,shapesBase:'urn:root',data:'',resources:{'urn:child':`<urn:child> <${owl}imports> <urn:root> .`}};
check(run(rootCycle).report.results.length,1);
check(run({...rootCycle,resources:{...rootCycle.resources,'urn:root':rootText}}).report.results.length,1);
check(run({...rootCycle,resources:{...rootCycle.resources,'urn:root':''}}).status,'resource-error');
const deepShapes=`<urn:level0> <${sh}targetNode> <urn:focus> . `+Array.from({length:1024},(_,i)=>`<urn:level${i}> <${sh}node> <urn:level${i+1}> .`).join('\n');
check(run({shapes:deepShapes,data:''}).status,'validation-failure');
fs.mkdirSync('artifacts',{recursive:true});
fs.writeFileSync('artifacts/bridge-checks.json',JSON.stringify({checks,passed:checks,failed:0},null,2)+'\n');
console.log(`${checks}/${checks} JSON bridge boundary checks passed.`);
