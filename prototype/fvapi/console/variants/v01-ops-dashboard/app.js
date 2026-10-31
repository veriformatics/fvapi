const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pretty = o => esc(JSON.stringify(o, null, 2));
let entries = [], sortKey = 'id', descending = false;
async function api(path, body) {
  const response = await fetch('/v0/' + path, body === undefined ? {} : {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const data = await response.json();
  return {data, status:response.status};
}
function badge(status) { return `<span class="badge ${status === 'recorded' ? 'recorded' : ''}">${status === 'recorded' ? 'Recorded only' : 'Replay available'}</span>`; }
function heading(title, description) { return `<div class="heading"><div><h1>${title}</h1><p class="muted">${description}</p></div><button id="refresh">Refresh</button></div>`; }
function bindRefresh() { $('#refresh').onclick = init; }
function catalogTable(compact = false) {
  return `<div class="toolbar"><input id="filter" aria-label="Filter catalog" placeholder="Filter entries"><select id="kind" aria-label="Entry kind"><option value="">All kinds</option>${[...new Set(entries.map(e=>e.kind))].map(k=>`<option>${esc(k)}</option>`).join('')}</select></div><div class="tablewrap"><table><thead><tr><th><button data-sort="id">Entry ↕</button></th>${compact?'':'<th><button data-sort="kind">Kind ↕</button></th>'}<th><button data-sort="replay_status">Replay ↕</button></th></tr></thead><tbody id="rows"></tbody></table></div><p class="meta" id="count"></p>`;
}
function bindCatalog(compact = false) {
  function draw() {
    const q = $('#filter').value.toLowerCase(), k = $('#kind').value;
    const list = entries.filter(e=>(!k || e.kind===k) && (e.title+' '+e.id+' '+e.claim).toLowerCase().includes(q)).sort((a,b)=>String(a[sortKey]).localeCompare(String(b[sortKey]))*(descending?-1:1));
    $('#rows').innerHTML = list.map(e=>`<tr><td><button class="entry-link" data-entry="${esc(e.id)}">${esc(e.id)}</button><p>${esc(e.title)}</p></td>${compact?'':`<td>${esc(e.kind)}</td>`}<td>${badge(e.replay_status)}</td></tr>`).join('') || '<tr><td colspan="3">No entries match. Change the filter.</td></tr>';
    $('#count').textContent = `${list.length} of ${entries.length} returned entries. Health count may include entries not returned by this fixture.`;
    document.querySelectorAll('[data-entry]').forEach(b=>b.onclick=()=>location.hash='entry/'+encodeURIComponent(b.dataset.entry));
  }
  $('#filter').oninput = draw; $('#kind').onchange = draw;
  document.querySelectorAll('[data-sort]').forEach(b=>b.onclick=()=>{descending=sortKey===b.dataset.sort?!descending:false;sortKey=b.dataset.sort;draw();});
  draw();
}
function evidence(e) {
  return `<div class="top"><span>${badge(e.replay.status)}</span><a href="#catalog" aria-label="Close entry">Close</a></div><div class="meta">${esc(e.id)} / ${esc(e.kind)}</div><h2>${esc(e.title)}</h2>${e.replay.status==='recorded'?'<div class="warning"><strong>Not re-run by fvapi.</strong><br>This is a recorded prototype stub. The transcript comes from an earlier run, not a fresh verification.</div>':''}<p>${esc(e.claim)}</p><div class="pair"><span>Subject</span><strong>${esc(e.subject.name)} ${esc(e.subject.version)}</strong><span>Toolchain</span><span>${esc(e.toolchain)}</span><span>Requires</span><span>${esc(e.requires.join(', '))}</span></div><h3>Statements to inspect</h3>${e.statements.map(s=>`<div class="meta">${esc(s.name)} — ${esc(s.file)}:${s.line}</div><pre>${esc(s.text)}</pre>`).join('')}<h3>Proof closure</h3>${e.closure.map(f=>`<div class="file"><strong>${esc(f.path)}</strong> <span class="meta">${f.bytes.toLocaleString()} bytes</span><code>sha256 ${esc(f.sha256)}</code></div>`).join('')}<h3>Replay on your machine</h3><p class="meta">${esc(e.replay.note)}</p><pre id="command">${esc(e.replay.command)}</pre><div class="actions"><button id="copy">Copy replay command</button><a class="button" href="/v0/bundles/${encodeURIComponent(e.id)}.tar.gz">Download bundle</a><a href="#check/${encodeURIComponent(e.id)}">Check input</a></div><h3>Expected axioms</h3><code>${esc(e.replay.expect_axioms.join(', ') || 'None')}</code>${e.replay.transcript?`<h3>Recorded transcript</h3><pre>${esc(e.replay.transcript)}</pre>`:''}<h3>Licence and notices</h3><p>${esc(e.licence.spdx)}</p>${e.licence.third_party.length?e.licence.third_party.map(n=>`<p>${esc(n.name)}: ${esc(n.spdx)}<br>${esc(n.source)}</p>`).join(''):'<p class="meta">No third-party notices listed.</p>'}<h3>Source</h3><pre>${esc(e.source.repo)}\ncommit ${esc(e.source.commit)}\n${esc(e.source.paths.join('\n'))}</pre>`;
}
async function showEntry(id) {
  $('#main').innerHTML=heading('Catalog','Inspect an entry without losing the inventory.')+`<div class="split"><section>${catalogTable(true)}</section><section class="drawer" id="drawer">Loading entry…</section></div>`;
  bindRefresh(); bindCatalog(true);
  const r=await api('catalog/'+encodeURIComponent(id));
  if(r.status!==200){$('#drawer').textContent=r.data.detail+' Choose another catalog entry.';return;}
  $('#drawer').innerHTML=evidence(r.data);
  $('#copy').onclick=async()=>{try{await navigator.clipboard.writeText(r.data.replay.command);$('#copy').textContent='Command copied';}catch{$('#copy').textContent='Select the command above to copy';}};
}
async function lookup(preset) {
  $('#main').innerHTML=heading('Look up','Find an existing proof. A miss becomes demand, not an agent request.')+`<section class="panel"><form id="lookup-form"><div class="form-grid"><div><div class="field"><label for="lookup-key">Match by</label><select id="lookup-key"><option value="spec_id">Specification ID</option><option value="artifact_sha256">Artifact SHA256</option><option value="statement">Statement text</option></select></div><div class="field"><label for="query">Value to find</label><textarea id="query" style="min-height:115px">vf.contrast-2x2</textarea></div><button class="primary">Look up</button></div><div class="notice"><h2>Keep the proof, not our verdict.</h2><p>A hit identifies a library entry. Download its bundle, inspect its statement, and replay it on your own machine.</p></div></div></form><div id="result" class="result" role="status"></div></section>`;
  bindRefresh();
  $('#lookup-form').onsubmit=async ev=>{ev.preventDefault();const r=await api('lookup',{[$('#lookup-key').value]:$('#query').value});$('#result').innerHTML=r.data.hit?`<div class="notice"><h2>Entry found</h2><p>${esc(r.data.entry.title)}</p><p>Matched on ${esc(r.data.matched_on)}. Answer ${esc(r.data.answer_id)}.</p><a class="button" href="#entry/${encodeURIComponent(r.data.entry_id)}">Inspect proof and replay</a></div>`:`<div class="warning"><h2>${r.data.logged?'No match. Logged as demand.':'Lookup failed'}</h2><p>${esc(r.data.detail)}</p><a href="#demand">View demand</a></div>`;};
  if(preset){if(preset==='miss')$('#query').value='no.such-spec';$('#lookup-form').requestSubmit();}
}
async function check(id='vf.contrast-2x2',preset='') {
  const r=await api('catalog/'+encodeURIComponent(id));
  const e=r.data;
  $('#main').innerHTML=heading('Check input','Run a proved checker, then re-check the result locally.')+`<section class="panel"><form id="check-form"><div class="field"><label for="check-id">Library entry</label><select id="check-id">${entries.map(x=>`<option value="${esc(x.id)}" ${x.id===id?'selected':''}>${esc(x.id)} (${esc(x.kind)})</option>`).join('')}</select></div>${!e.check?'<div class="warning">This entry has no input checker. Choose a checker entry to run a check.</div>':''}<div class="field"><label for="input">Input JSON</label><textarea class="check-editor" id="input" spellcheck="false">${pretty(e.check?.example_input || {})}</textarea></div><div class="actions"><button class="primary">Run check</button><button type="button" id="reset">Reset example</button><span class="meta">The input is editable.</span></div></form><div class="result" id="result" role="status"></div></section>`;
  bindRefresh(); $('#check-id').onchange=()=>location.hash='check/'+encodeURIComponent($('#check-id').value);
  $('#reset').onclick=()=>$('#input').value=JSON.stringify(e.check?.example_input || {},null,2);
  $('#check-form').onsubmit=async ev=>{ev.preventDefault();let input;try{input=JSON.parse($('#input').value);}catch{$('#result').innerHTML='<div class="warning">The input is not valid JSON. Correct it and run the check again.</div>';return;}const c=await api('checks/'+encodeURIComponent($('#check-id').value),input);$('#result').innerHTML=c.status===200?`<div class="${c.data.verdict==='accept'?'notice':'warning'}"><h2>${c.data.verdict==='accept'?'Accepted':'Rejected'}</h2><p>${c.data.verdict==='accept'?'The input passed the checker. Re-check it locally before use.':'The input did not pass. Correct the weights and run the check again.'}</p><p class="meta">${esc(c.data.ran_on)} / ${c.data.elapsed_ms} ms / exit ${c.data.exit_code} / ${esc(c.data.answer_id)}</p><pre>${pretty(c.data.output)}</pre><h3>Re-check locally</h3><pre>${esc(c.data.recheck.command)}</pre></div>`:`<div class="warning"><h2>Check unavailable (${c.status})</h2><p>${esc(c.data.detail)}</p><p>Choose an entry of kind checker to run input.</p></div>`;};
  if(preset==='reject'){const v=JSON.parse($('#input').value);v.rows[0].weights[0]=1;$('#input').value=JSON.stringify(v,null,2);}
  if(preset){$('#check-form').requestSubmit();}
}
async function logs(which) {
  const {data}=await api(which);
  $('#main').innerHTML=heading(which==='demand'?'Demand':'Answers',which==='demand'?'Unmatched requests guide library development. No agent works on an individual miss.':'Lookup and checker answers, newest first.')+(which==='demand'?`<h2>Demand by key</h2>${table(['Key','Requests'],data.by_key.map(x=>[x.key,x.count]))}<h2 style="margin-top:26px">Recent misses</h2>${table(['Miss','Time','Query'],data.misses.map(x=>[x.miss_id,x.at,JSON.stringify(x.query)]))}`:table(['Answer','Time','Operation','Entry','Verdict'],data.answers.map(x=>[x.answer_id,x.at,x.kind,x.entry_id,x.verdict||'Entry found'])));
  bindRefresh();
}
function table(head,rows){return `<div class="tablewrap"><table class="logtable"><thead><tr>${head.map(x=>`<th>${x}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row.map(x=>`<td><code>${esc(x)}</code></td>`).join('')}</tr>`).join('')||`<tr><td colspan="${head.length}">No records yet. Run a lookup or check to get started.</td></tr>`}</tbody></table></div>`;}
async function route(){
  const [view,arg]=location.hash.slice(1).split('/');
  const active=view?.startsWith('lookup')?'lookup':view?.startsWith('check')?'check':view==='entry'||view==='recorded'?'catalog':view||'catalog';
  document.querySelectorAll('nav a').forEach(a=>a.classList.toggle('active',a.hash==='#'+active));
  try{
    if(view==='entry'||view==='recorded')await showEntry(decodeURIComponent(arg || (view==='recorded'?'fva.glm-iround':'vf.contrast-2x2')));
    else if(view?.startsWith('lookup'))await lookup(view==='lookup-hit'?'hit':view==='lookup-miss'?'miss':null);
    else if(view?.startsWith('check'))await check(decodeURIComponent(arg || (view==='check-409'?'fva.glm-iround':'vf.contrast-2x2')),view==='check-reject'?'reject':view==='check-accept'||view==='check-409'?'run':'');
    else if(view==='demand'||view==='answers')await logs(view);
    else{$('#main').innerHTML=heading('Catalog','Library entries and their replay status.')+catalogTable();bindRefresh();bindCatalog();}
    document.body.dataset.ready='true';
  }catch(error){$('#main').innerHTML=`<div class="warning"><h1>Cannot load this view</h1><p>${esc(error.message)}</p><button onclick="location.reload()">Try again</button></div>`;document.body.dataset.ready='error';}
}
async function init(){try{const [h,c]=await Promise.all([api('health'),api('catalog')]);entries=c.data.entries;$('#health').innerHTML=`<strong>${esc(h.data.host)}</strong><span>${esc(h.data.lean)}</span><span><strong>${h.data.entries}</strong> library entries</span><span class="muted">${esc(h.data.version)}</span>`;await route();}catch(e){$('#main').textContent='The service is unavailable. Reload the page to try again.';}}
window.addEventListener('hashchange',route);init();
