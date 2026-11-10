const $ = id => document.getElementById(id);
const EX = 'https://example.org/';
const RDF_TYPE = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type';
const DCAT = 'http://www.w3.org/ns/dcat#';
const DCT = 'http://purl.org/dc/terms/';
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const short = value => String(value ?? '').replace(/^https:\/\/example\.org\//, 'ex:').replace(/^http:\/\/www\.w3\.org\/ns\/shacl#/, 'sh:').replace(/^http:\/\/www\.w3\.org\/ns\/dcat#/, 'dcat:').replace(/^http:\/\/purl\.org\/dc\/terms\//, 'dct:');
const tail = value => String(value ?? '').split(/[\/#]/).filter(Boolean).at(-1) || String(value ?? '');
const svgText = (text, max = 24) => escapeHtml(String(text).length > max ? String(text).slice(0, max - 1) + '…' : text);
let dataBundle, scenario = 'people', currentGraph = '', initialGraph = '', proposalGraph = '', lastResponse = null;
let lastDelta = null, busy = true, ready = false, hasProposal = false, graphView = 'current', sequence = 0;
const logs = [], pending = new Map();
let worker;

function announce(message) { $('live-status').textContent = message; }
function config() { return dataBundle?.[scenario]; }
function setBusy(value) {
  busy = value;
  const unavailable = !ready || !config();
  for (const id of ['remove-button','repair-button','company-name','reset-button']) $(id).disabled = value || unavailable;
  $('export-graph').disabled = value || !currentGraph;
  $('export-report').disabled = value || !lastResponse;
  for (const tab of document.querySelectorAll('.workspace-tab')) tab.disabled = value;
  $('view-proposal').disabled = value || !hasProposal;
  $('view-current').disabled = value;
  $('graph-stage').setAttribute('aria-busy', String(value));
  $('result-panel').setAttribute('aria-busy', String(value));
}
function addLog(message, kind = '') {
  const date = new Date();
  logs.unshift({message, kind, time:date.toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',second:'2-digit'})});
  if (logs.length > 8) logs.length = 8;
  $('activity-log').innerHTML = logs.map(log => `<li class="log-${escapeHtml(log.kind)}"><time>${log.time}</time><span>${escapeHtml(log.message)}</span></li>`).join('');
}
function rpc(payload) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error('引擎执行超时。请刷新页面重试。'));
    }, 45000);
    pending.set(id, {resolve, reject, timer});
    worker.postMessage({id, payload});
  });
}
function assertResponse(response, expected) {
  if (response.status !== expected) throw new Error(response.message || `${response.status}：${JSON.stringify(response.problems || response.diagnostics || [])}`);
  return response;
}
async function normalize(data) {
  return assertResponse(await rpc({operation:'audit', shapes:'', data}), 'supported').dataRdf;
}
function canonicalLines(text) { return text.split(/\r?\n/).map(line => line.trim()).filter(Boolean); }
function proposedGraph(before, additions, removals) {
  const graph = new Set(canonicalLines(before));
  for (const line of canonicalLines(removals)) graph.delete(line);
  for (const line of canonicalLines(additions)) graph.add(line);
  return [...graph].join('\n') + '\n';
}
function decodeLiteral(value) {
  return value.replace(/\\U([a-fA-F0-9]{8})|\\u([a-fA-F0-9]{4})|\\([tbnrf"'\\])/g, (_, wide, narrow, char) => {
    if (wide || narrow) return String.fromCodePoint(parseInt(wide || narrow,16));
    return ({t:'\t',b:'\b',n:'\n',r:'\r',f:'\f','"':'"',"'":"'",'\\':'\\'})[char];
  });
}
// This reader is only for the visual summary of canonical N-Triples emitted by the engine.
// Parsing, validation and transaction decisions always run inside MoonSHACL.
function triples(text) {
  const output = [];
  for (const line of canonicalLines(text)) {
    const match = line.match(/^(<[^>]*>|_:[^\s]+)\s+<([^>]*)>\s+(.+)\s+\.$/u);
    if (!match) continue;
    const [, subject, predicate, object] = match;
    const literal = object.match(/^"((?:[^"\\]|\\.)*)"(?:@[\w-]+|\^\^<[^>]*>)?$/u);
    output.push({subject:subject.startsWith('<') ? subject.slice(1,-1) : subject, predicate, value:literal ? decodeLiteral(literal[1]) : object.startsWith('<') ? object.slice(1,-1) : object, literal:Boolean(literal), rawObject:object});
  }
  return output;
}
function pathLabel(path) {
  if (!path) return '—';
  if (path.predicate) return short(path.predicate);
  if (path.sequence) return path.sequence.map(pathLabel).join(' → ');
  if (path.alternative) return path.alternative.map(pathLabel).join(' | ');
  if (path.inverse) return '^' + pathLabel(path.inverse);
  for (const [key, symbol] of [['zeroOrMore','*'],['oneOrMore','+'],['zeroOrOne','?']]) if (path[key]) return '(' + pathLabel(path[key]) + ')' + symbol;
  return JSON.stringify(path);
}
function focusNodes() { return new Set((lastResponse?.report?.results || []).map(result => result.focusNode?.value)); }
function currentNameTriple() { return triples(currentGraph).find(t => t.subject === EX+'acme' && t.predicate === EX+'name'); }
function literal(value) { return JSON.stringify(value).replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029'); }

function renderPeopleGraph() {
  if ($('graph-stage').clientWidth < 520) return renderCompactPeopleGraph();
  $('people-graph').setAttribute('viewBox','0 0 760 420');
  $('people-graph').removeAttribute('data-compact');
  const displayed = triples(graphView === 'proposal' ? proposalGraph : currentGraph);
  const saved = triples(currentGraph), affected = focusNodes();
  const positions = {alice:[48,52],bob:[48,172],carol:[48,292],acme:[432,96],other:[432,292]};
  const names = id => displayed.filter(t => t.subject === EX+id && t.predicate === EX+'name').map(t=>t.value);
  const savedNames = id => saved.filter(t => t.subject === EX+id && t.predicate === EX+'name').map(t=>t.value);
  const relevantCompanies = new Set(displayed.filter(t => t.predicate === EX+'employer' && affected.has(t.subject)).map(t=>t.value));
  const edges = displayed.filter(t => t.predicate === EX+'employer').map(t => {
    const from = positions[tail(t.subject)], to = positions[tail(t.value)];
    if (!from || !to) return '';
    const error = affected.has(t.subject);
    const [x1,y1] = [from[0]+171,from[1]+34], [x2,y2] = [to[0],to[1]+34];
    return `<path d="M ${x1} ${y1} C ${x1+85} ${y1}, ${x2-85} ${y2}, ${x2-7} ${y2}" fill="none" stroke="${error?'#d18e77':'#b0c5b1'}" stroke-width="${error?'2.2':'1.6'}" marker-end="url(#arrow-${error?'error':'normal'})"/><rect x="${Math.round((x1+x2)/2)-33}" y="${Math.round((y1+y2)/2)-10}" width="69" height="20" rx="4" fill="${error?'#fff3ec':'#fff'}"/><text x="${Math.round((x1+x2)/2)+1}" y="${Math.round((y1+y2)/2)+3}" font-size="10" fill="${error?'#ae705b':'#82947e'}" text-anchor="middle">employer</text>`;
  }).join('');
  const people = ['alice','bob','carol'].map(id => {
    const [x,y] = positions[id], error = affected.has(EX+id), name = names(id)[0] || id;
    return `<g><rect class="graph-node" x="${x}" y="${y}" width="171" height="68" rx="11" fill="${error?'#fff0e8':'#fff'}" stroke="${error?'#d39079':'#d6e1d2'}" stroke-width="1.3"/><circle cx="${x+29}" cy="${y+33}" r="15" fill="${error?'#f7dcd0':'#edf2e7'}"/><circle cx="${x+29}" cy="${y+28}" r="4" fill="${error?'#b8755c':'#789074'}"/><path d="M ${x+22} ${y+40} Q ${x+22} ${y+32} ${x+29} ${y+33} Q ${x+36} ${y+32} ${x+36} ${y+40}" fill="${error?'#b8755c':'#789074'}"/><text x="${x+54}" y="${y+31}" font-size="14" font-weight="550" fill="#25453b">${svgText(name,14)}</text><text x="${x+54}" y="${y+48}" font-size="9" fill="${error?'#ac735e':'#92a08c'}">${error?'校验报告的关注节点':'Person'}</text>${error?`<circle cx="${x+158}" cy="${y+12}" r="4" fill="#c57b61"/>`:''}</g>`;
  }).join('');
  const companies = ['acme','other'].map(id => {
    const [x,y] = positions[id], values = names(id), error = relevantCompanies.has(EX+id), missing = !values.length;
    return `<g><rect x="${x}" y="${y}" width="260" height="91" rx="11" fill="${missing?'#fff5ef':'#f0f5e9'}" stroke="${error?'#d39079':'#cbdcc5'}" stroke-width="1.3" ${missing?'stroke-dasharray="5 4"':''}/><rect x="${x+17}" y="${y+16}" width="24" height="26" rx="4" fill="${error?'#efd7c8':'#dce8d2'}"/><path d="M ${x+23} ${y+22} h 3 M ${x+31} ${y+22} h 3 M ${x+23} ${y+28} h 3 M ${x+31} ${y+28} h 3 M ${x+27} ${y+34} v 8" stroke="${error?'#b58268':'#7d9b70'}" stroke-width="2"/><text x="${x+52}" y="${y+29}" font-size="13" font-weight="550" fill="#446441">${id==='acme'?'共享公司':'独立公司'}</text><text x="${x+52}" y="${y+44}" font-size="9" fill="#8ba181">${escapeHtml('ex:'+id)}</text><rect x="${x+17}" y="${y+56}" width="226" height="23" rx="5" fill="${missing?'#ffe9dc':'#fff'}"/><text x="${x+27}" y="${y+71}" font-size="9" fill="#8a9e7f">name</text><text x="${x+67}" y="${y+72}" font-size="11" font-weight="500" fill="${missing?'#b06f52':'#51704a'}">${missing?'∅ 名称缺失':svgText(values.join(' / '),24)}</text>${missing&&savedNames(id).length?`<title>本次提案删除了名称；已保存图仍保留 ${escapeHtml(savedNames(id).join(' / '))}。</title>`:''}</g>`;
  }).join('');
  const mode = graphView === 'proposal' ? '本次提案' : '已保存图';
  $('people-graph').innerHTML = `<title id="svg-title">${mode}：人物与公司的关联图</title><desc id="svg-desc">${escapeHtml(`Alice 和 Bob 的 employer 指向 ${names('acme').join('、') || '缺少名称的共享公司'}；Carol 指向 ${names('other').join('、') || '缺少名称的独立公司'}。校验报告关注节点：${[...affected].map(tail).join('、') || '无'}。`)}</desc><defs><marker id="arrow-normal" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M0 0 L8 4 L0 8" fill="#b0c5b1"/></marker><marker id="arrow-error" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M0 0 L8 4 L0 8" fill="#d18e77"/></marker></defs>${edges}${people}${companies}<text x="48" y="406" font-size="9" fill="#9caa92">规则路径：Person → employer → name</text><text x="692" y="406" font-size="9" text-anchor="end" fill="#9caa92">${escapeHtml(mode)}</text>`;
}
function renderCompactPeopleGraph() {
  $('people-graph').setAttribute('viewBox','0 0 340 403');
  $('people-graph').setAttribute('data-compact','true');
  const shown=triples(graphView==='proposal'?proposalGraph:currentGraph), affected=focusNodes();
  const names=id=>shown.filter(t=>t.subject===EX+id&&t.predicate===EX+'name').map(t=>t.value);
  const positions={alice:[6,30],bob:[6,151],carol:[6,272],acme:[195,91],other:[195,272]};
  const related=new Set(shown.filter(t=>t.predicate===EX+'employer'&&affected.has(t.subject)).map(t=>t.value));
  const edges=shown.filter(t=>t.predicate===EX+'employer').map(t=>{
    const from=positions[tail(t.subject)],to=positions[tail(t.value)];
    if(!from||!to)return '';
    const error=affected.has(t.subject), x1=from[0]+112,y1=from[1]+34,x2=to[0],y2=to[1]+34;
    const midY=Math.round((y1+y2)/2);
    return `<path d="M ${x1} ${y1} C ${x1+29} ${y1}, ${x2-29} ${y2}, ${x2-6} ${y2}" fill="none" stroke="${error?'#cc8c73':'#b0c5b1'}" stroke-width="1.7" marker-end="url(#compact-arrow-${error?'error':'normal'})"/><rect x="125" y="${midY-10}" width="63" height="19" rx="4" fill="${error?'#fff1e8':'#fff'}"/><text x="156" y="${midY+3}" font-size="10" fill="${error?'#b2775f':'#8b9b83'}" text-anchor="middle">employer</text>`;
  }).join('');
  const people=['alice','bob','carol'].map(id=>{
    const [x,y]=positions[id],error=affected.has(EX+id);
    return `<g><rect x="${x}" y="${y}" width="112" height="68" rx="10" fill="${error?'#fff0e8':'#fff'}" stroke="${error?'#ce8d75':'#d5dfd0'}" stroke-width="1.3"/><circle cx="${x+22}" cy="${y+26}" r="12" fill="${error?'#f3d6c9':'#e8efdf'}"/><circle cx="${x+22}" cy="${y+22}" r="3.5" fill="${error?'#b78268':'#829575'}"/><path d="M ${x+16} ${y+32} Q ${x+16} ${y+25} ${x+22} ${y+26} Q ${x+28} ${y+25} ${x+28} ${y+32}" fill="${error?'#b78268':'#829575'}"/><text x="${x+41}" y="${y+31}" font-size="14" font-weight="550" fill="#314e3e">${svgText(names(id)[0]||id,8)}</text><text x="${x+12}" y="${y+54}" font-size="10" fill="${error?'#ad765f':'#8a9b7d'}">${error?'● 校验关注节点':'Person'}</text></g>`;
  }).join('');
  const companies=['acme','other'].map(id=>{
    const [x,y]=positions[id],values=names(id),missing=!values.length,error=related.has(EX+id);
    return `<g><title>${escapeHtml(values.join(' / ')||'名称缺失')}</title><rect x="${x}" y="${y}" width="139" height="92" rx="10" fill="${missing?'#fff3e9':'#eef4e5'}" stroke="${error?'#ce8d75':'#cad9be'}" stroke-width="1.3" ${missing?'stroke-dasharray="4 4"':''}/><rect x="${x+12}" y="${y+15}" width="19" height="24" rx="4" fill="${error?'#ebd0bf':'#d8e4cb'}"/><path d="M ${x+17} ${y+21} h 2 M ${x+24} ${y+21} h 2 M ${x+17} ${y+27} h 2 M ${x+24} ${y+27} h 2 M ${x+21} ${y+33} v 6" stroke="${error?'#af7d62':'#7c966a'}" stroke-width="1.6"/><text x="${x+41}" y="${y+27}" font-size="12" font-weight="550" fill="#4a6540">${id==='acme'?'共享公司':'独立公司'}</text><text x="${x+41}" y="${y+42}" font-size="10" fill="#8b9f7f">ex:${id}</text><rect x="${x+10}" y="${y+56}" width="119" height="25" rx="5" fill="${missing?'#ffe6d5':'#fff'}"/><text x="${x+17}" y="${y+72}" font-size="9" fill="#9aab8b">name</text><text x="${x+46}" y="${y+72}" font-size="11" fill="${missing?'#b07858':'#5c7650'}">${missing?'∅ 名称缺失':svgText(values.join(' / '),13)}</text></g>`;
  }).join('');
  const mode=graphView==='proposal'?'本次提案':'已保存图';
  $('people-graph').innerHTML=`<title id="svg-title">${mode}：人物与公司的关联图</title><desc id="svg-desc">${escapeHtml(`Alice、Bob 指向共享公司 ${names('acme').join('、')||'（名称缺失）'}，Carol 指向独立公司 ${names('other').join('、')}。校验报告关注节点：${[...affected].map(tail).join('、')||'无'}。`)}</desc><defs><marker id="compact-arrow-normal" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="4" markerHeight="4" orient="auto-start-reverse"><path d="M0 0 L8 4 L0 8" fill="#b0c5b1"/></marker><marker id="compact-arrow-error" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="4" markerHeight="4" orient="auto-start-reverse"><path d="M0 0 L8 4 L0 8" fill="#cc8c73"/></marker></defs>${edges}${people}${companies}<text x="7" y="389" font-size="9.5" fill="#8a9a7b">规则：Person → employer → name</text><text x="334" y="389" text-anchor="end" font-size="9.5" fill="#8a9a7b">${escapeHtml(mode)}</text>`;
}
function renderCatalogue() {
  const cfg = config(), shown = triples(graphView === 'proposal' ? proposalGraph : currentGraph), affected = focusNodes();
  const ids = [...new Set(shown.filter(t => t.predicate === RDF_TYPE && [DCAT+'Dataset',DCAT+'Distribution',DCAT+'Catalog'].includes(t.value)).map(t=>t.subject))];
  if (cfg.recordIri && !ids.includes(cfg.recordIri)) ids.unshift(cfg.recordIri);
  const records = ids.slice(0,8).map(id => {
    const rows = shown.filter(t=>t.subject===id), format = rows.find(t=>t.predicate===DCT+'format')?.value;
    const title = rows.find(t=>t.predicate===DCT+'title')?.value || rows.find(t=>t.predicate==='http://www.w3.org/2000/01/rdf-schema#label')?.value || (format ? tail(format) + ' 分发' : tail(id));
    const urls = rows.filter(t=>[DCAT+'accessURL',DCAT+'downloadURL'].includes(t.predicate));
    const kind = rows.find(t=>t.predicate===RDF_TYPE)?.value;
    const idLabel = tail(id).length > 28 ? tail(id).slice(0,25) + '…' : tail(id);
    return `<article class="catalogue-record ${affected.has(id)?'affected':''}"><h3>${escapeHtml(title)}</h3><small title="${escapeHtml(id)}">${escapeHtml(idLabel)}</small><p>${escapeHtml(tail(kind))} · ${rows.length} 条陈述${affected.has(id)?' · 校验报告关注节点':''}</p>${urls.slice(0,2).map(t=>`<p title="${escapeHtml(t.value)}">${escapeHtml(tail(t.predicate))} · ${escapeHtml(t.value.length>65?t.value.slice(0,62)+'…':t.value)}</p>`).join('')}</article>`;
  }).join('');
  $('catalogue-graph').innerHTML = `<div class="catalogue-summary"><strong>${canonicalLines(graphView==='proposal'?proposalGraph:currentGraph).length}</strong><p>条 RDF 陈述 · ${graphView==='proposal'?'本次提案':'已保存图'}<br>公开目录元数据快照</p></div><div class="catalogue-records">${records}</div><p class="catalogue-source">公开元数据快照 · 应用规则，非官方全量认证 / 非外部采用。更新仅作用于当前浏览器中的副本。</p>`;
}
function renderGraph() {
  if (!config()) return;
  if (scenario === 'people') renderPeopleGraph(); else renderCatalogue();
  $('view-current').classList.toggle('active',graphView==='current');
  $('view-current').setAttribute('aria-pressed',String(graphView==='current'));
  $('view-proposal').classList.toggle('active',graphView==='proposal');
  $('view-proposal').setAttribute('aria-pressed',String(graphView==='proposal'));
  $('triple-count').textContent = canonicalLines(currentGraph).length + ' 条已保存';
  $('raw-data').textContent = currentGraph;
  if (!lastResponse?.report) return;
  const rejected = lastResponse.status==='updated' && !lastResponse.committed;
  const affected = focusNodes().size;
  if (rejected) $('graph-caption').textContent = graphView==='proposal' ? `这是未提交的提案视图。引擎报告 ${affected} 个关注节点违反约束；可切换到已保存图核对原数据。` : `预检已拒绝本次更新。这里展示引擎返回的已保存图，原数据保留；高亮的是拒绝报告中的关联节点。`;
  else if (lastResponse.status==='updated') $('graph-caption').textContent = '更新通过预检并已提交。当前图来自引擎的 graphRdf 返回值，可导出后再次校验。';
  else $('graph-caption').textContent = lastResponse.report.conforms ? (scenario==='people'?'初始图符合规则。试着删除共享公司名称，观察 Alice、Bob 与 Carol 的校验结果。':'当前快照通过本演示的应用规则。尝试删除分发的访问地址，观察预检如何阻止不完整数据进入目录。') : '当前数据未通过所选规则；下方列出了实际校验结果。';
}
function renderReport(response) {
  lastResponse = response;
  const report = response.report;
  if (!report) throw new Error('引擎响应缺少 report。');
  const isUpdate = response.status === 'updated', rejected = isUpdate && !response.committed;
  const okay = isUpdate ? response.committed : report.conforms;
  $('result-panel').className = 'result-panel ' + (okay?'success':'rejected');
  $('result-icon').textContent = okay ? '✓' : '×';
  $('result-eyebrow').textContent = isUpdate ? (okay?'TRANSACTION COMMITTED':'TRANSACTION REJECTED') : 'INITIAL VALIDATION';
  $('result-title').textContent = isUpdate ? (okay?'更新已提交，图已安全替换':'更新被拒绝，已保存图保持不变') : (okay?'初始数据通过校验':'初始数据未通过校验');
  $('result-description').textContent = isUpdate ? `committed = ${response.committed} · conforms = ${report.conforms} · ${report.results.length} 项校验结果` : `conforms = ${report.conforms} · ${report.results.length} 项校验结果 · 当前使用${scenario==='people'?'人物关联规则':'应用规则'}`;
  $('checked').textContent = report.work?.checked ?? '—';
  $('reused').textContent = report.work?.reused ?? '—';
  $('report-results').innerHTML = report.results.map((result,index) => `<article class="report-card"><div class="report-card-head"><strong>${escapeHtml(short(result.focusNode?.value))}</strong><span>${escapeHtml(tail(result.resultSeverity?.value) || '结果')} ${index+1}</span></div><dl><dt>路径</dt><dd><code>${escapeHtml(pathLabel(result.resultPath))}</code></dd><dt>约束</dt><dd>${escapeHtml(short(result.sourceConstraintComponent))}</dd><dt>形状</dt><dd>${escapeHtml(short(result.sourceShape?.value))}</dd></dl>${result.resultMessage?.length?`<p class="result-message">${escapeHtml(result.resultMessage.map(m=>m.value).join(' · '))}</p>`:''}</article>`).join('');
  $('raw-json').textContent = JSON.stringify(response,null,2);
  $('session-tag').textContent = isUpdate ? (rejected?'提案已拒绝':'更新已保存') : '初始会话';
  renderGraph();
  announce($('result-title').textContent + '。' + $('result-description').textContent);
}
function displayError(error) {
  const message = error instanceof Error ? error.message : String(error);
  lastResponse = null;
  $('load-error').hidden = false;
  $('load-error').textContent = '执行失败：' + message;
  $('result-panel').className = 'result-panel error';
  $('result-title').textContent = '执行未完成';
  $('result-description').textContent = '没有应用本次操作。请查看上方错误说明。';
  $('result-icon').textContent = '!';
  $('report-results').replaceChildren();
  $('checked').textContent = '—';
  $('reused').textContent = '—';
  $('raw-json').textContent = '本次执行未生成有效引擎响应。\n' + message;
  $('graph-caption').textContent = '本次操作未完成；图中仍展示最近一次由引擎返回的已保存数据。';
  $('graph-loading').hidden = true;
  announce('执行失败。' + message);
  addLog('执行失败：' + message,'rejected');
}
function showBusy(message) {
  setBusy(true);
  $('load-error').hidden = true;
  $('result-panel').className = 'result-panel busy';
  $('result-title').textContent = message;
  $('result-icon').textContent = '…';
  $('result-eyebrow').textContent = 'RUNNING MOONSHACL';
  $('result-description').textContent = '正在 Web Worker 中运行真实校验引擎。';
  announce(message);
}
function externalLink(href,label) {
  try { const url = new URL(href); if (!['https:','http:'].includes(url.protocol)) return escapeHtml(label); return `<a href="${escapeHtml(url.href)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)} ↗</a>`; } catch { return escapeHtml(label); }
}
function scenarioCopy() {
  const cfg = config(), people = scenario==='people';
  $('people-graph').toggleAttribute('hidden', !people);
  $('catalogue-graph').hidden = people;
  $('catalogue-context').hidden = people;
  $('graph-kicker').textContent = people?'THE CONNECTED DATA':'A REAL CATALOGUE SNAPSHOT';
  $('graph-title').textContent = people?'三个人，两家公司，一个共享名称。':cfg.title || '真实开放数据目录';
  $('graph-description').textContent = people?'Alice 和 Bob 共享 Acme。规则要求，每个人沿 employer → name 都能找到公司名称。':cfg.description || '从公开元数据导入目录，校验、定位问题并修复。';
  $('remove-title').textContent = people?'删除共享公司的名称':'删除一项分发的访问地址';
  $('remove-copy').textContent = people?'看似只改了一家公司，实际会影响哪些人？':'模拟一次导入错误：移除必需的 accessURL。';
  $('remove-button-label').textContent = people?'尝试删除名称':'尝试删除访问地址';
  $('repair-title').textContent = people?'在同一次更新中修复':'用来源记录中的地址替换';
  $('repair-copy').textContent = people?'将删除与新增组成原子更新，通过后才提交。':'使用原记录声明的下载地址，在本地副本中完成原子替换。';
  $('replacement-label').textContent = people?'新的公司名称':'来源提供的替换地址';
  $('company-name').value = people?'Acme Limited':cfg.replacementUrl || triplesFromDeltaUrl(cfg.additions) || '使用来源记录中声明的下载地址';
  $('company-name').readOnly = !people;
  $('company-name').maxLength = people ? 160 : 4000;
  $('source-shapes').textContent = cfg.shapes;
  $('source-data').textContent = cfg.data;
  let attribution = people ? '此场景为自建集成示例，用于展示共享节点依赖与原子提交。' : `数据来源：${externalLink(cfg.sourceUrl || '',cfg.sourceLabel || '公开目录')}。公开元数据快照 · 应用规则，非官方全量认证 / 非外部采用。仅更新浏览器内的副本。`;
  const official = cfg.officialValidation || cfg.officialSummary;
  if (cfg.baseline) {
    attribution += `<br>官方 base · 原始查询切片（${escapeHtml(cfg.sourceTriples)} 条）：${escapeHtml(cfg.baseline.rawOfficialResults)} 项问题，conforms = ${escapeHtml(cfg.baseline.rawOfficialConforms)}。<br>官方 base · 导入投影（${escapeHtml(cfg.importedTriples)} 条）：${escapeHtml(cfg.baseline.projectedOfficialResults)} 项问题，conforms = ${escapeHtml(cfg.baseline.projectedOfficialConforms)}。<br>${escapeHtml(cfg.baseline.note)}<br>现场交互单独使用自定义本地应用规则，结果见实时校验区。`;
  } else if (official) {
    const result = official.report || official;
    const count = Array.isArray(result.results)?result.results.length:result.results;
    attribution += `<br>已记录的官方 DCAT-AP 基础规则基线：conforms = ${escapeHtml(result.conforms)}${count!==undefined?'，'+escapeHtml(count)+' 项结果':''}。${escapeHtml(official.description || cfg.officialValidationDescription || '这与本演示的应用规则不同；投影范围可能缺少被引用对象的类型信息。')}`;
  }
  $('source-attribution').innerHTML = attribution;
  if (!people) {
    const baseline = cfg.baseline;
    $('catalogue-context').innerHTML = `<p>${externalLink(cfg.sourceUrl || '',cfg.sourceLabel || '公开数据来源')}<span> · ${escapeHtml(cfg.sourceTriples || '—')} 条原始陈述 → ${escapeHtml(cfg.importedTriples || canonicalLines(cfg.data).length)} 条导入投影</span></p>${baseline?`<details><summary>官方基础规则与本演示应用规则，有什么区别？</summary><p>官方 base · 原始查询切片（${escapeHtml(cfg.sourceTriples)} 条）：${escapeHtml(baseline.rawOfficialResults)} 项问题。<br>官方 base · 导入投影（${escapeHtml(cfg.importedTriples)} 条）：${escapeHtml(baseline.projectedOfficialResults)} 项问题。</p><p>${escapeHtml(baseline.note)}</p><p>自定义本地应用规则：现场运行的 conforms 见下方实时校验区。完整约束可在「校验规则与原始数据」中查看。</p>${cfg.metadataLicense?`<p>门户元数据许可：${externalLink(cfg.metadataLicense.url,cfg.metadataLicense.id)}。${cfg.source?.retrievedAt?'快照获取日期：'+escapeHtml(cfg.source.retrievedAt.slice(0,10))+'。':''}未下载或重分发底层空气质量观测数据。</p>`:''}</details>`:''}`;
  }
}
function triplesFromDeltaUrl(text) { return String(text || '').match(/(?:<http:\/\/www\.w3\.org\/ns\/dcat#accessURL>|dcat:accessURL)\s+<([^>]*)>/)?.[1]; }
async function loadScenario(reset = false) {
  const cfg = config();
  if (!cfg) {
    $('workspace').hidden = true;
    $('result-panel').hidden = true;
    $('unavailable').hidden = false;
    currentGraph = ''; lastResponse = null;
    setBusy(false);
    return;
  }
  $('workspace').hidden = false;
  $('result-panel').hidden = false;
  $('unavailable').hidden = true;
  currentGraph = ''; initialGraph = ''; proposalGraph = ''; hasProposal = false; lastResponse = null; lastDelta = null; graphView = 'current';
  $('delta-removals').textContent = '暂无更新';
  $('delta-additions').textContent = '暂无更新';
  $('report-results').replaceChildren();
  scenarioCopy();
  showBusy(reset?'正在重置并重新校验':'正在校验初始数据');
  $('graph-loading').hidden = false;
  try {
    currentGraph = await normalize(cfg.data);
    initialGraph = currentGraph;
    const result = assertResponse(await rpc({operation:'validate',shapes:cfg.shapes,data:currentGraph}), 'validated');
    renderReport(result);
    addLog((reset?'已重置':'已加载') + (scenario==='people'?'共享对象场景':'真实目录快照') + '；' + (result.report.conforms?'校验通过':'校验未通过'),result.report.conforms?'success':'rejected');
  } catch (error) { displayError(error); }
  finally { $('graph-loading').hidden = true; setBusy(false); }
}
async function applyUpdate(repair) {
  if (busy || !ready) return;
  const cfg = config();
  let additions = '', removals = cfg.removals;
  if (scenario==='people') {
    const name = currentNameTriple();
    if (!name) { displayError(new Error('当前已保存图中没有可替换的共享公司名称。请重置场景。')); return; }
    removals = `<${EX}acme> <${EX}name> ${name.rawObject} .`;
    if (repair) {
      const nextName = $('company-name').value;
      if (!nextName.trim()) { $('company-name').focus(); announce('请输入新的公司名称。'); $('company-name').setCustomValidity('请输入新的公司名称。'); $('company-name').reportValidity(); return; }
      $('company-name').setCustomValidity('');
      additions = `<${EX}acme> <${EX}name> ${literal(nextName)} .`;
    }
  } else {
    // Use the live graph's accessURL after any prior accepted replacement.
    const removalLines = triples(cfg.removals);
    const target = removalLines.find(t=>t.predicate===DCAT+'accessURL');
    const live = target && triples(currentGraph).filter(t=>t.subject===target.subject && t.predicate===target.predicate);
    if (live?.length) removals = live.map(t=>`<${t.subject}> <${t.predicate}> ${t.rawObject} .`).join('\n');
    if (repair) additions = cfg.additions || cfg.repairAdditions || '';
  }
  showBusy(repair?'正在预检原子替换':'正在预检删除操作');
  try {
    const [normalizedAdd, normalizedRemove] = await Promise.all([normalize(additions),normalize(removals)]);
    const candidate = proposedGraph(currentGraph,normalizedAdd,normalizedRemove);
    const response = assertResponse(await rpc({operation:'update',shapes:cfg.shapes,data:currentGraph,additions,removals}), 'updated');
    if (typeof response.graphRdf !== 'string') throw new Error('更新响应缺少已保存图。');
    currentGraph = response.graphRdf;
    proposalGraph = candidate;
    lastDelta = {additions,removals};
    hasProposal = true;
    graphView = response.committed?'current':'proposal';
    $('delta-removals').textContent = removals || '（无）';
    $('delta-additions').textContent = additions || '（无）';
    renderReport(response);
    addLog((repair?'原子替换':'删除操作') + (response.committed?'已提交':'被拒绝') + `；${response.report.results.length} 项结果`,response.committed?'success':'rejected');
  } catch (error) { displayError(error); }
  finally { setBusy(false); }
}
function download(name,text,type) {
  const url = URL.createObjectURL(new Blob([text],{type}));
  const link = document.createElement('a'); link.href = url; link.download = name;
  document.body.append(link); link.click(); link.remove();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
  addLog('已导出 ' + name);
  announce('已导出 ' + name);
}
for (const tab of document.querySelectorAll('.workspace-tab')) {
  tab.addEventListener('click',async () => {
    if (busy || tab.dataset.scenario===scenario) return;
    scenario = tab.dataset.scenario;
    for (const item of document.querySelectorAll('.workspace-tab')) {
      const selected = item===tab; item.classList.toggle('active',selected); item.setAttribute('aria-selected',String(selected)); item.tabIndex = selected?0:-1;
    }
    $('scenario-panel').setAttribute('aria-labelledby',tab.id);
    await loadScenario();
  });
  tab.addEventListener('keydown',event => {
    if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key) || busy) return;
    event.preventDefault();
    const tabs = [...document.querySelectorAll('.workspace-tab')];
    const next = event.key==='Home'?tabs[0]:event.key==='End'?tabs.at(-1):tabs[(tabs.indexOf(tab)+(event.key==='ArrowRight'?1:tabs.length-1))%tabs.length];
    next.focus(); next.click();
  });
}
$('remove-button').addEventListener('click',()=>applyUpdate(false));
$('repair-button').addEventListener('click',()=>applyUpdate(true));
$('reset-button').addEventListener('click',()=>loadScenario(true));
$('company-name').addEventListener('input',()=> $('company-name').setCustomValidity(''));
$('company-name').addEventListener('keydown',event=>{if(event.key==='Enter'&&!busy){event.preventDefault();applyUpdate(true);}});
$('view-current').addEventListener('click',()=>{graphView='current';renderGraph();});
$('view-proposal').addEventListener('click',()=>{if(hasProposal){graphView='proposal';renderGraph();}});
$('export-graph').addEventListener('click',()=>download(`moonshacl-${scenario}-saved.nt`,currentGraph,'application/n-triples;charset=utf-8'));
$('export-report').addEventListener('click',()=>download(`moonshacl-${scenario}-result.json`,JSON.stringify(lastResponse,null,2)+'\n','application/json;charset=utf-8'));
let compactLayout;
if (typeof ResizeObserver !== 'undefined') new ResizeObserver(entries=>{
  const compact=entries[0].contentRect.width<520;
  if(compact!==compactLayout){compactLayout=compact;if(currentGraph&&scenario==='people')renderGraph();}
}).observe($('graph-stage'));

async function start() {
  setBusy(true);
  try {
    const engineReady = new Promise((resolve,reject) => {
      worker = new Worker(new URL('./worker.js',import.meta.url),{type:'module'});
      const timer = setTimeout(()=>reject(new Error('引擎加载超时。请确认 moonshacl.mjs 已构建且通过 HTTP 服务访问。')),25000);
      worker.onmessage = ({data}) => {
        if (data.ready) {clearTimeout(timer);resolve();return;}
        const call = pending.get(data.id);
        if (!call) return;
        clearTimeout(call.timer);pending.delete(data.id);
        if (data.error) call.reject(new Error(data.error)); else call.resolve(data.result);
      };
      worker.onerror = event => {
        clearTimeout(timer);
        ready=false;
        $('engine-dot').className='engine-dot error';
        $('engine-status').textContent='引擎不可用';
        const error=new Error(event.message || '无法加载校验引擎。请使用本地 HTTP 服务打开演示。');
        reject(error);
        for (const call of pending.values()){clearTimeout(call.timer);call.reject(error);}
        pending.clear();
        displayError(error);
        setBusy(false);
      };
    });
    const bundleReady = fetch(new URL('./demo-data.json',import.meta.url)).then(response=>{
      if(!response.ok)throw new Error(`无法加载演示数据（HTTP ${response.status}）。请先执行演示构建。`);
      return response.json();
    });
    const [,bundle]=await Promise.all([engineReady,bundleReady]);
    dataBundle=bundle; ready=true;
    $('engine-dot').className='engine-dot ready';
    $('engine-status').textContent='真实引擎已就绪';
    await loadScenario();
  } catch(error) {
    ready=false;
    $('engine-dot').className='engine-dot error';
    $('engine-status').textContent='加载失败';
    displayError(error);setBusy(false);
  }
}
start();

async function loadPerformance() {
  try {
    const response=await fetch(new URL('./performance.json',import.meta.url));
    if(!response.ok)throw new Error('Benchmark unavailable');
    const benchmark=await response.json();
    const scenarios=benchmark.scenarios;
    if(!Array.isArray(scenarios)||!scenarios.length)throw new Error('Missing measurements');
    const medians=s=>[s.measurements?.previewInvalidCached?.medianMs,s.measurements?.rebuildAndValidateInvalidFullHashed?.medianMs];
    if(scenarios.some(s=>medians(s).some(n=>!Number.isFinite(n)||n<=0)))throw new Error('Invalid measurements');
    const ratios=scenarios.map(s=>{const[preview,full]=medians(s);return full/preview;});
    const slower=ratios.filter(r=>r<1).length;
    const samples=benchmark.methodology?.samples;
    $('performance-summary').textContent=`${scenarios.length} 个合成场景，每项 ${samples} 次采样。「哈希删除、重建图并全量校验 ÷ 缓存预检」的中位耗时比值为 ${Math.min(...ratios).toFixed(2)}–${Math.max(...ratios).toFixed(2)}×，其中 ${slower}/${scenarios.length} 个场景的缓存预检更慢。`;
    const round2=benchmark.previousRoundComparison?.scenarios?.filter(s=>s.previousWasSlower) || [];
    if(round2.length){
      $('performance-round2').textContent=`第二轮针对上轮剩余的 ${round2.length} 个场景：${round2.map(s=>`${s.people.toLocaleString('zh-CN')} 人全部受影响，${s.beforePreviewMedianMs.toFixed(2)} → ${s.afterPreviewMedianMs.toFixed(2)} ms`).join('；')}。这类提案没有缓存命中，收益来自候选图构造的优化；前后是不同时间的测量，完整条件见报告。`;
      $('performance-round2').hidden=false;
    }
    const previousSlow=benchmark.historicalComparison?.scenarios?.filter(s=>s.wasSlowerThanOriginalFull) || [];
    const reductions=previousSlow.map(s=>s.previewLatencyReductionPercent);
    if(reductions.length && reductions.every(n=>Number.isFinite(n) && n>0)){
      $('performance-improvements').textContent=`原来的 ${reductions.length} 个慢场景，缓存预检中位延迟下降 ${Math.min(...reductions).toFixed(1)}%–${Math.max(...reductions).toFixed(1)}%。这是与同机旧版存档的前后对照，完整耗时、历史样本及测量边界见报告。`;
      $('performance-improvements').hidden=false;
    }
    const maxPeople=Math.max(...scenarios.map(s=>s.people));
    const rows=['shared-company','all-people'].map(name=>scenarios.find(s=>s.people===maxPeople&&s.name===name)).filter(Boolean);
    $('performance-details').hidden=false;
    $('performance-table').innerHTML=`<caption>${maxPeople.toLocaleString('zh-CN')} 人合成关联图 · 中位耗时（毫秒）</caption><thead><tr><th scope="col">更新影响范围</th><th scope="col">缓存预检</th><th scope="col">重建并全量校验</th></tr></thead><tbody>${rows.map(s=>{const[preview,full]=medians(s);return `<tr><th scope="row">${s.name==='shared-company'?'局部共享':'全部影响'}<small>${s.affectedPeople.toLocaleString('zh-CN')} 人 / ${s.people.toLocaleString('zh-CN')} 人</small></th><td>${preview.toFixed(2)}</td><td>${full.toFixed(2)}</td></tr>`;}).join('')}</tbody>`;
    $('performance-environment').textContent=`${benchmark.environment?.cpu || 'CPU 信息见报告'} · ${benchmark.environment?.node || 'Node'} · ${benchmark.environment?.platform || ''} / ${benchmark.environment?.arch || ''}。固定机器实测，浏览器演示未在此计时。`;
  } catch {
    $('performance-summary').textContent='暂无法读取基准 JSON。可通过下方入口查看完整报告与原始数据；此处不展示未核实的性能数字。';
    $('performance-details').hidden=true;
  }
}
loadPerformance();
