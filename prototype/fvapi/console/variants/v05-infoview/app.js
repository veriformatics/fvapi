const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pretty = v => JSON.stringify(v, null, 2);
const params = new URLSearchParams(location.search);
const state = params.get('state') || 'catalog';
const checkerId = 'vf.contrast-2x2';
let entries = [], entry;
window.__errors = [];
window.addEventListener('error', e => window.__errors.push(e.message));
window.addEventListener('unhandledrejection', e => window.__errors.push(String(e.reason)));
async function api(path, body) {
  const response = await fetch('/v0/' + path, body === undefined ? {} : {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
  return {ok:response.ok, status:response.status, data:await response.json()};
}
function section(title, content) { return `<section class="info-section"><h3>${title}</h3>${content}</section>`; }
function tree() {
  const query = $('#filter').value.toLowerCase();
  $('#tree').innerHTML = entries.filter(e => [e.id,e.title,e.claim].join(' ').toLowerCase().includes(query)).map(e => `<div><a class="tree-entry ${entry?.id === e.id?'selected':''}" href="?state=entry&id=${encodeURIComponent(e.id)}"><span aria-hidden="true">${e.kind === 'checker'?'◇':'▱'}</span> ${esc(e.id)}<small>${esc(e.kind)} / ${esc(e.replay_status)}</small></a>${entry?.id === e.id ? `<div class="file-tree">${(entry.closure||[]).map(f=>`▧ ${esc(f.path)}`).join('<br>')}</div>`:''}</div>`).join('') || '<p class="empty">No entries match. Try another name.</p>';
}
function info(e) {
  if (!e) { $('#info').innerHTML = section('A caller checks the answer', '<p>Open an entry to inspect its statements, proof closure and replay command.</p><p>Every answer must carry enough evidence for an independent replay.</p>') + section('Workspace', '<p>Catalog: browse the library.</p><p>Request: look up a statement or run a checker.</p><p>Demand: inspect unanswered requests.</p>'); return; }
  const recorded = e.replay?.status === 'recorded' || e.replay_status === 'recorded';
  $('#info').innerHTML = section('Replay state', `<span class="flag ${recorded?'recorded':''}">${recorded?'! Recorded; not re-run by fvapi':'✓ Real replay entry'}</span><p>${recorded?'The transcript comes from an earlier run. It is not a fresh verification.':'This entry supports a real replay. Re-run the delivered files yourself.'}</p><p>${esc(e.replay?.note||'')}</p>`) +
  section('Expected axioms', `<ul>${(e.replay?.expect_axioms||[]).map(a=>`<li><code>${esc(a)}</code></li>`).join('')}</ul>${e.replay?'':'<p>Open the full entry to inspect the axioms.</p>'}`) +
  section('Proof closure', (e.closure||[]).map(f=>`<p><strong>${esc(f.path)}</strong><br>${esc(f.bytes)} bytes<br><code>sha256 ${esc(f.sha256)}</code></p>`).join('') || '<p>Full closure is not available in this summary.</p>') +
  section('Licence + notices', `<p>${esc(e.licence?.spdx||e.licence_spdx)}</p>${e.licence?(e.licence.third_party.length?e.licence.third_party.map(n=>`<p>${esc(n.name)}<br>${esc(n.spdx)}<br>${esc(n.source)}</p>`).join(''):'<p>No third-party notices listed.</p>'):''}`) +
  section('Source', `<p>${esc(e.source?.repo||'See full entry')}</p><code>${esc(e.source?.commit||'')}</code><p>${(e.source?.paths||[]).map(esc).join('<br>')}</p><p>${esc(e.toolchain)}</p><p>${(e.requires||[]).map(esc).join(', ')}</p>`);
}
function statement(e) {
  const statements = e.statements || [];
  $('#editor').innerHTML = `<div class="file-tab">${esc(statements[0]?.file || e.id)} <span aria-hidden="true">×</span></div><div class="document"><div class="kind">${esc(e.kind)} / ${esc(e.id)}</div><h1>${esc(e.title)}</h1><p>${esc(e.claim)}</p></div>${statements.map(s=>`<div class="code-title">${esc(s.file)}:${esc(s.line)} <span class="comment"> / ${esc(s.name)}</span></div><div class="code-buffer">${s.text.split('\n').map((line,i)=>`<div class="code-line"><span class="line-number">${s.line+i}</span><span class="lean">${esc(line)}</span></div>`).join('')}</div>`).join('')}<section class="messages"><h2>Replay terminal</h2><p class="message-note">Read the statement above. Check that it matches your intended claim before you run the proof.</p>${e.replay?`<pre class="response" id="command">${esc(e.replay.command)}</pre><button class="copy" id="copy">Copy replay command</button><a class="bundle" href="/v0/bundles/${encodeURIComponent(e.id)}.tar.gz">Download proof bundle</a>${e.replay.transcript?`<h3>Recorded transcript</h3><pre class="response">${esc(typeof e.replay.transcript==='string'?e.replay.transcript:pretty(e.replay.transcript))}</pre>`:''}`:'<p>Full entry is unavailable in this mock. Select another entry.</p>'}</section>`;
  $('#copy')?.addEventListener('click', async () => { try {await navigator.clipboard.writeText(e.replay.command);$('#copy').textContent='Copied replay command';} catch {$('#copy').textContent='Select and copy the command above';} });
}
function catalog() {
  info(null);
  $('#editor').innerHTML = `<div class="file-tab">Library / catalog</div><div class="document"><div class="kind">Available proofs + checkers</div><h1>Find the statement.<br>Inspect the evidence.</h1><p>The library gives you a starting point, not a substitute for verification. Open an entry to read what it actually proves.</p><span class="comment">${entries.length} entries returned by the API</span></div>${entries.map(e=>`<a class="catalog-row" href="?state=entry&id=${encodeURIComponent(e.id)}"><div class="row-id">${esc(e.id)}</div><h3>${esc(e.title)}</h3><p>${esc(e.claim)}</p><div class="row-meta"><span>${esc(e.kind)}</span><span>${e.replay_status==='recorded'?'! Recorded; not re-run by fvapi':'✓ Real replay entry'}</span></div></a>`).join('')}`;
}
function result(r, check) {
  const title = r.status === 404 ? 'No match; logged as demand' : r.status === 409 ? 'No checker for this entry' : !r.ok ? 'Request failed' : check ? (r.data.verdict === 'accept' ? 'Accepted by the checker' : 'Rejected by the checker') : 'Matching entry found';
  $('#result').innerHTML = `<p class="result-title ${!r.ok||r.data.verdict==='reject'?'error':''}">${esc(title)} <span class="comment">/ HTTP ${r.status}</span></p>${r.status===409?'<p>Select an entry with a checker and run it again.</p>':''}${r.status===404?'<p>The query is in the demand log. Try another identifier or statement.</p>':''}<pre class="response">${esc(pretty(r.data))}</pre>`;
  $('#status').textContent = title;
}
async function request() {
  const check = state.startsWith('check');
  if (!check) info(null);
  $('#editor').innerHTML = `<div class="file-tab">Requests / ${check?'checker-input.json':'lookup.json'}</div><div class="form"><div class="kind">${check?'Run a proved checker':'Find a library answer'}</div><h1>${check?'Check your input':'Look up a statement'}</h1><div class="request-toggle"><a href="?state=request">Lookup</a><span>/</span><a href="?state=check">Check input</a></div>${check?`<label for="check-id">Entry</label><select id="check-id">${entries.map(e=>`<option value="${esc(e.id)}">${esc(e.id)} (${esc(e.kind)})</option>`).join('')}</select><label for="payload">Input JSON (editable)</label><textarea id="payload" spellcheck="false"></textarea><div class="form-actions"><button class="primary" id="run-check">Run check</button><button id="reset-input">Restore example</button></div>`:`<label for="lookup-key">Match by</label><select id="lookup-key"><option value="spec_id">Specification identifier</option><option value="artifact_sha256">Artifact SHA-256</option><option value="statement">Statement text</option></select><label for="query">Query</label><textarea id="query" style="min-height:100px" spellcheck="false"></textarea><div class="form-actions"><button class="primary" id="lookup">Look up</button></div>`}</div><section class="messages"><h2>Messages</h2><div id="result" aria-live="polite"><p>Run a request to see the API response.</p></div></section>`;
  if(check) {
    $('#payload').value = pretty(entry.check.example_input);
    $('#check-id').value = entry.id;
    if(state==='check-reject') {const bad=JSON.parse($('#payload').value);bad.rows[0].weights[0]=1;$('#payload').value=pretty(bad);}
    if(state==='check-409') $('#check-id').value=entries.find(e=>e.kind!=='checker')?.id||entry.id;
    const showCheckEntry=()=>info($('#check-id').value===entry.id?entry:entries.find(e=>e.id===$('#check-id').value));
    $('#check-id').onchange=showCheckEntry;showCheckEntry();
    const run=async()=>{try{const body=JSON.parse($('#payload').value);result(await api('checks/'+encodeURIComponent($('#check-id').value),body),true);}catch(e){$('#result').textContent='The input is not valid JSON. Correct it and run the check again. '+e.message;}};
    $('#run-check').onclick=run;$('#reset-input').onclick=()=>{$('#payload').value=pretty(entry.check.example_input);};
    if(['check-accept','check-reject','check-409'].includes(state)) await run();
  } else {
    $('#query').value=state==='lookup-miss'?'missing.example':checkerId;
    const run=async()=>{const r=await api('lookup',{[$('#lookup-key').value]:$('#query').value});result(r,false);info(r.ok?r.data.entry:null);};
    $('#lookup').onclick=()=>run().catch(fail);
    if(state==='lookup-hit'||state==='lookup-miss') await run();
  }
}
async function log(kind) {
  const r=await api(kind);info(null);
  $('#editor').innerHTML=`<div class="file-tab">Service / ${kind}.json</div><div class="document"><div class="kind">Request history</div><h1>${kind==='demand'?'Unanswered requests':'Answers returned'}</h1><p>${kind==='demand'?'Misses identify where the library can become useful. A miss is logged as demand; it does not trigger an LLM.':'Lookups and checks returned by the service. A returned answer still needs an independent replay.'}</p></div><div class="log"><pre>${esc(pretty(r.data))}</pre></div>`;
}
function fail(e){window.__errors.push(String(e));$('#editor').innerHTML=`<div class="document"><h1>The API could not be reached.</h1><p>Start the service and reload this page.</p><pre>${esc(String(e))}</pre></div>`;$('#status').textContent='API unavailable';}
async function init(){
  const c=await api('catalog');if(!c.ok)throw Error('Catalog HTTP '+c.status);entries=c.data.entries;
  $('#connection').textContent='Relative API /v0';$('#filter').oninput=tree;
  const id=params.get('id')||(state==='recorded'?'fva.glm-iround':checkerId);
  if(state!=='catalog'&&state!=='demand'&&state!=='answers'){
    const r=await api('catalog/'+encodeURIComponent(id));entry=r.ok?r.data:entries.find(e=>e.id===id);if(!entry)throw Error('Entry not found');
  }
  tree();info(entry);
  const active=state==='catalog'?'catalog':['demand','answers'].includes(state)?state:state==='entry'||state==='recorded'?'entry':'request';
  document.querySelector(`[data-tab="${active}"]`)?.classList.add('active');
  if(state==='catalog')catalog();else if(state==='entry'||state==='recorded')statement(entry);else if(['demand','answers'].includes(state))await log(state);else await request();
  $('#status').textContent='Ready / '+(entry?.id||state);document.body.dataset.ready='true';
}
init().catch(fail);
