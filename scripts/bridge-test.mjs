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
console.log('17/17 JSON bridge boundary checks passed.');
