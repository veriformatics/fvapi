const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const json = v => esc(JSON.stringify(v, null, 2));
let entries = [];
async function api(path, body) {
  const response = await fetch('/v0/' + path, body === undefined ? {} : {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  return {status:response.status, data:await response.json()};
}
function line(name, value) { return `<dt>${esc(name)}</dt><dd>${esc(value)}</dd>`; }
function receipt(title, body, total, warning = false) {
  const paper = document.createElement('article'); paper.className = 'receipt';
  paper.innerHTML = `<h2>fvapi</h2><p class="sub">${esc(title)} / library counter</p>${body}<div class="total"><span>Result</span><span class="${warning?'failure':''}">${esc(total)}</span></div><p class="end">Keep the evidence. Re-check locally.<br>---------------- tear here ----------------</p>`;
  $('#receipts').append(paper); $('#status').textContent = `${title} printed.`;
  return paper;
}
function entryBody(e) {
  return `<dl>${line('Entry',e.id)}${line('Kind',e.kind)}${line('Subject',e.subject.name+' / '+e.subject.version)}</dl><h3>What is claimed</h3><p>${esc(e.claim)}</p>${e.replay.status==='recorded'?'<p class="stamp">Recorded stub<br>Not re-run by fvapi</p>':''}<h3>Read the statement</h3>${e.statements.map(s=>`<p>${esc(s.name)}</p><pre>${esc(s.text)}</pre><p class="hash">${esc(s.file)}:${s.line}</p>`).join('')}<h3>Closure line items</h3>${e.closure.map(f=>`<p>${esc(f.path)} / ${esc(f.bytes)} bytes</p><p class="hash">SHA-256<br>${esc(f.sha256)}</p>`).join('')}<h3>Replay on your machine</h3><p>${esc(e.toolchain)}</p><p>${esc(e.requires.join(', '))}</p><pre class="command">${esc(e.replay.command)}</pre><button class="copy" type="button">Copy replay command</button><p>${esc(e.replay.note)}</p>${e.replay.transcript?`<pre>${esc(e.replay.transcript)}</pre>`:''}<h3>Expected axioms</h3><p>${esc(e.replay.expect_axioms.join(', ')||'None')}</p><h3>Licence and notices</h3><p>${esc(e.licence.spdx)}</p>${e.licence.third_party.length?e.licence.third_party.map(n=>`<p>${esc(n.name)}: ${esc(n.spdx)}<br>${esc(n.source)}</p>`).join(''):'<p>No third-party notices listed.</p>'}<h3>Source</h3><dl>${line('Repository',e.source.repo)}${line('Commit',e.source.commit)}${line('Paths',e.source.paths.join('\n'))}</dl>${e.subject.artifact?`<h3>Subject artifact</h3><pre>${json(e.subject.artifact)}</pre>`:''}<p><a href="/v0/bundles/${encodeURIComponent(e.id)}.tar.gz">Download proof bundle</a></p>`;
}
async function printEntry(id) {
  const {status,data:e} = await api('catalog/'+encodeURIComponent(id));
  if(status!==200) {
    const summary = entries.find(x=>x.id===id);
    return receipt('Entry unavailable',`<p class="stamp">${summary?.replay_status==='recorded'?'Recorded stub. Not re-run by fvapi.':'Entry not available.'}</p><p>${esc(e.detail)} Open another catalog entry.</p>`,'Unavailable',true);
  }
  receipt('Entry details',entryBody(e),e.replay.status==='recorded'?'Recorded':'Replay supplied',e.replay.status==='recorded');
}
async function lookup(query) {
  const {status,data:d} = await api('lookup',query);
  if(status===404) return receipt('Back-order slip',`<p class="stamp">No library match<br>${d.logged?'Logged as demand':'Demand was not logged'}</p><dl>${line('Miss id',d.miss_id)}</dl><pre>${json(d.query)}</pre><p>${esc(d.detail)}</p><p>Try another entry id, artifact hash or statement.</p>`,'No match',true);
  if(status!==200) throw Error(d.detail);
  receipt('Lookup answer',`<dl>${line('Answer id',d.answer_id)}${line('Matched on',d.matched_on)}</dl>`+entryBody(d.entry),'Match found');
}
async function loadExample() {
  const {status,data} = await api('catalog/'+encodeURIComponent($('#check-id').value));
  if(status!==200||!data.check) { $('#status').textContent='This entry has no checker. Choose a checker entry to load an example.'; return; }
  $('#input').value=JSON.stringify(data.check.example_input,null,2); return data.check.example_input;
}
async function runCheck(id,input) {
  const {status,data:d} = await api('checks/'+encodeURIComponent(id),input);
  if(status!==200) return receipt('Check not run',`<dl>${line('Entry',id)}${line('HTTP status',status)}</dl><p class="stamp">${esc(d.error)}</p><p>${esc(d.detail)}</p><p>Choose a checker entry from the catalog, then load its example input.</p>`,'Not run',true);
  receipt('Input check',`<dl>${line('Answer id',d.answer_id)}${line('Entry',d.entry_id)}${line('Ran on',d.ran_on)}${line('Elapsed',d.elapsed_ms+' ms')}${line('Exit code',d.exit_code)}${line('Input SHA-256',d.input_sha256)}</dl><h3>Checker output</h3><pre>${json(d.output)}</pre><h3>Re-check on your machine</h3><pre>${esc(d.recheck.command)}</pre><p><a href="${esc(d.recheck.bundle)}">Download proof bundle</a></p>`,d.verdict,d.verdict!=='accept');
}
async function printLog(kind) {
  const {status,data:d}=await api(kind); if(status!==200) throw Error(d.detail);
  const rows=kind==='demand'?d.misses:d.answers;
  let body=rows.length?rows.map(r=>`<dl>${Object.entries(r).map(([k,v])=>line(k,typeof v==='object'?JSON.stringify(v):v)).join('')}</dl><p>--------------------------------</p>`).join(''):'<p>No requests yet. Make a lookup or run a check.</p>';
  if(kind==='demand')body+=`<h3>Demand counts by key</h3>${d.by_key.map(r=>`<p>${esc(r.key)}<br>Requests: ${esc(r.count)}</p>`).join('')}`;
  receipt(kind==='demand'?'Back-order ledger':'Answer ledger',body,String(rows.length)+(rows.length===1?' record':' records'));
}
async function safe(fn) {try {await fn();} catch(e){$('#status').textContent='Request failed. '+e.message+' Try again when the API is available.';}}
$('#lookup').onsubmit=e=>{e.preventDefault();safe(()=>lookup({[$('#key').value]:$('#query').value}));};
$('#check').onsubmit=e=>{e.preventDefault();safe(()=>runCheck($('#check-id').value,JSON.parse($('#input').value)));};
$('#example').onclick=()=>safe(loadExample);
$('#demand').onclick=()=>safe(()=>printLog('demand'));
$('#answers').onclick=()=>safe(()=>printLog('answers'));
$('#receipts').onclick=async e=>{if(e.target.matches('.copy')) {try{await navigator.clipboard.writeText(e.target.previousElementSibling.textContent);e.target.textContent='Copied';}catch{$('#status').textContent='Copy failed. Select the replay command and copy it manually.';}}};
safe(async()=>{
  const {status,data}=await api('catalog');if(status!==200)throw Error(data.detail);entries=data.entries;
  $('#count').textContent=entries.length+' entries';
  $('#catalog').innerHTML=entries.map(e=>`<div class="catalog-item"><div><button data-id="${esc(e.id)}">${esc(e.title)}</button><small>${esc(e.id)} / ${esc(e.kind)}</small></div><div class="replay">${e.replay_status==='recorded'?'Recorded stub<br>Not re-run by fvapi':'Replay supplied'}</div></div>`).join('');
  $('#catalog').onclick=e=>{const b=e.target.closest('[data-id]');if(b)safe(()=>printEntry(b.dataset.id));};
  const state=new URLSearchParams(location.search).get('state')||'catalog';
  if(state==='catalog')receipt('Counter open','<p>Choose an entry from the board above to inspect its claim, proof files and replay instructions.</p><p>Or make a request at the till. Each response becomes a receipt on this roll.</p>','Ready');
  if(state==='entry'||state==='mobile')await printEntry('vf.contrast-2x2');
  if(state==='recorded')await printEntry('fva.glm-iround');
  if(state==='lookup-hit')await lookup({spec_id:'vf.contrast-2x2'});
  if(state==='lookup-miss')await lookup({spec_id:'no.such-entry'});
  if(state.startsWith('check-')){
    $('#check-panel').open=true;const input=await loadExample();
    if(state==='check-reject'){input.rows[1].weights[0]=2;$('#input').value=JSON.stringify(input,null,2);}
    const id=state==='check-409'?'fva.glm-iround':'vf.contrast-2x2';$('#check-id').value=id;await runCheck(id,input);
  }
  if(state==='demand'||state==='answers')await printLog(state);
  document.body.dataset.ready=state;
});
