import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

// Generated fixtures, tests, the host bridge and executable are not core code.
const files = fs.readdirSync('src').filter(f => f.endsWith('.mbt') && !/_(wb)?test\.mbt$/.test(f))
  .map(f => `src/${f}`).concat(['src/turtle/parse.mbt','src/xpath_regex/regex.mbt','src/xpath_regex/nfa.mbt']).sort();
const rows = files.map(file => {
  const text = fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
  // The audited files use whole-line // comments, not block comments.
  assert(!text.includes('/*'), `${file}: extend the counter for block comments`);
  const lines = text.trimEnd().split('\n');
  const code = lines.filter(line => line.trim() && !line.trimStart().startsWith('//'));
  const substantive = code.filter(line => !/^[\s{}()[\],;]+$/.test(line));
  return {file, physical: lines.length, excludingBlankAndComment: code.length, excludingDelimiterOnly: substantive.length};
});
const totals = Object.fromEntries(['physical','excludingBlankAndComment','excludingDelimiterOnly']
  .map(key => [key, rows.reduce((sum, row) => sum + row[key], 0)]));
const report = {method:'Whole-line // comments and blanks removed; strict count also excludes delimiter-only lines. Not an official contest determination.', excluded:['tests','generated conformance fixtures','generated Unicode tables and source data','demo','bridge','JavaScript host','dependencies'], files:rows, totals};
const target = process.argv[2] || 'artifacts/source-audit.json';
fs.mkdirSync(path.dirname(target), {recursive:true});
fs.writeFileSync(target, JSON.stringify(report, null, 2)+'\n');
console.log(JSON.stringify(totals));
