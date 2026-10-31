const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pretty = value => JSON.stringify(value, null, 2);
let checker, catalog, current, logKind = 'demand';
const history = [];
const presets = {
  catalog: ['GET', '/v0/catalog'], entry: ['GET', '/v0/catalog/vf.contrast-2x2'],
  recorded: ['GET', '/v0/catalog/fva.glm-iround'],
  'lookup-hit': ['POST', '/v0/lookup', {spec_id:'vf.contrast-2x2'}],
  'lookup-sha': ['POST', '/v0/lookup'], 'lookup-statement': ['POST', '/v0/lookup'],
  'lookup-miss': ['POST', '/v0/lookup', {spec_id:'unknown.specification'}],
  'check-accept': ['POST', '/v0/checks/vf.contrast-2x2'],
  'check-reject': ['POST', '/v0/checks/vf.contrast-2x2'],
  'check-409': ['POST', '/v0/checks/fva.glm-iround', {}]
};
function setPreset(name) {
  const p = presets[name] || presets.catalog;
  $('preset').value = name in presets ? name : 'catalog';
  $('method').value=p[0]; $('route').value=p[1];
  let body = p[2];
  if(name==='lookup-sha') body={artifact_sha256:catalog.entries.find(e=>e.subject?.artifact)?.subject.artifact.sha256 || ''};
  if(name==='lookup-statement') body={statement:checker.statements[0]?.text || ''};
  if (name==='check-accept'||name==='check-reject') {
    body=structuredClone(checker.check.example_input);
    if(name==='check-reject') body.rows[0].weights[0] += 1;
  }
  $('body').value=body === undefined ? '' : pretty(body);
  $('body-note').textContent=p[0]==='GET'?'GET requests have no body.':'Edit the JSON before you send it.';
}
function entryView(e) {
  const recorded=e.replay?.status==='recorded';
  return `<p class="entry-meta">${esc(e.id)} / ${esc(e.kind)}</p><h3>${esc(e.title)}</h3><p>${esc(e.claim)}</p>${recorded?'<div class="warning"><strong>Recorded proof. Not re-run by fvapi.</strong><br>This transcript comes from an earlier run. Re-run the bundle yourself.</div>':'<span class="badge">Replay available</span>'}<h4>Statements to match</h4>${(e.statements||[]).map(s=>`<p class="entry-meta">${esc(s.name)} / ${esc(s.file)}:${esc(s.line)}</p><pre>${esc(s.text)}</pre>`).join('')}<h4>Proof closure</h4>${(e.closure||[]).map(f=>`<div class="file">${esc(f.path)} <span class="entry-meta">${esc(f.bytes)} bytes</span><code class="hash">sha256 ${esc(f.sha256)}</code></div>`).join('')}<h4>Re-run locally</h4><button class="copy" id="copy">Copy replay command</button><pre id="command">${esc(e.replay?.command)}</pre><p class="entry-meta">${esc(e.toolchain)} / ${(e.requires||[]).map(esc).join(', ')}</p><p>${esc(e.replay?.note)}</p><h4>Expected axioms</h4><pre>${esc((e.replay?.expect_axioms||[]).join('\n') || 'None')}</pre>${e.replay?.transcript?`<h4>Recorded transcript</h4><pre>${esc(e.replay.transcript)}</pre>`:''}<h4>Licence and third-party notices</h4><p>${esc(e.licence?.spdx)}</p>${e.licence?.third_party?.length?e.licence.third_party.map(t=>`<p>${esc(t.name)}: ${esc(t.spdx)}<br>${esc(t.source)}</p>`).join(''):'<p>No third-party notices listed.</p>'}<h4>Source</h4><p>${esc(e.source?.repo)}<br>Commit: ${esc(e.source?.commit)}</p><pre>${esc((e.source?.paths||[]).join('\n'))}</pre><a href="/v0/bundles/${encodeURIComponent(e.id)}.tar.gz">Download proof bundle</a>`;
}
function render(data, status) {
  current=data; $('json').textContent=pretty(data);
  let html;
  if(data.entries) html=`<p class="entry-meta">${data.entries.length} library entries</p>${data.entries.map(e=>`<div class="catalog-entry"><button data-entry="${esc(e.id)}">${esc(e.title)}</button><p>${esc(e.claim)}</p><span class="badge">${esc(e.kind)}</span> ${e.replay_status==='recorded'?'<span class="bad">Recorded; not re-run by fvapi</span>':'<span class="good">Replay available</span>'}</div>`).join('')}`;
  else if(data.hit) html=`<p class="good"><strong>Match found</strong> / ${esc(data.answer_id)}</p>${entryView(data.entry)}`;
  else if(data.replay) html=entryView(data);
  else if(data.verdict) html=`<p class="entry-meta">Checker response / ${esc(data.entry_id)}</p><h3 class="verdict ${data.verdict==='reject'?'reject':''}">${data.verdict==='accept'?'Input accepted':'Input rejected'}</h3><p>${data.verdict==='accept'?'The submitted weights match the proved compilation.':'The submitted weights do not match. Restore the example or correct the weights and run the check again.'}</p><pre>${esc(pretty(data.output))}</pre><p class="entry-meta">Exit code ${esc(data.exit_code)} / ${esc(data.elapsed_ms)} ms / ${esc(data.ran_on)}</p><h4>Check it yourself</h4><p>The server answer is not a substitute for your own replay.</p><pre>${esc(data.recheck?.command)}</pre><a href="${esc(data.recheck?.bundle)}">Download checker bundle</a><h4>Input digest</h4><code class="hash">${esc(data.input_sha256)}</code>`;
  else if(status===404 && $('route').value==='/v0/lookup') html='<div class="warning"><strong>No match. Logged as demand.</strong><p>The library does not contain an answer for this query. Change the query or inspect the demand log.</p></div><pre>'+esc(pretty(data))+'</pre>';
  else if(status===409) html='<div class="warning"><strong>This entry has no runnable checker.</strong><p>Choose a checker entry, such as vf.contrast-2x2, and run the check again.</p></div><pre>'+esc(pretty(data))+'</pre>';
  else html='<pre>'+esc(pretty(data))+'</pre>';
  $('result').innerHTML=html;
  $('result').querySelectorAll('[data-entry]').forEach(b=>b.onclick=()=>{ $('method').value='GET'; $('route').value='/v0/catalog/'+encodeURIComponent(b.dataset.entry); $('body').value=''; send(); });
  if($('copy')) $('copy').onclick=async()=>{try{await navigator.clipboard.writeText(current.entry?.replay.command || current.replay.command);$('copy').textContent='Copied';}catch{$('copy').textContent='Select the command below to copy it';}};
}
async function send() {
  const method=$('method').value, route=$('route').value;
  if(!route.startsWith('/v0/')) {$('status').textContent='Use a route that starts with /v0/.';return;}
  $('send').disabled=true; $('status').textContent='Sending…';
  try {
    const options={method};
    if(method==='POST'){options.headers={'Content-Type':'application/json'};options.body=JSON.stringify(JSON.parse($('body').value || '{}'));}
    const start=performance.now(); const response=await fetch(route,options); const data=await response.json();
    $('status').textContent=`${response.status} / ${Math.round(performance.now()-start)} ms`;
    $('status').className=response.ok?'good':'bad';
    const item={method,route,body:$('body').value,data,status:response.status}; history.unshift(item);
    render(data,response.status); renderHistory(); await loadLogs();
  } catch(error) {$('status').className='bad';$('status').textContent='Request failed';$('result').textContent='The request could not be sent. Check the JSON and the server connection. '+error.message;}
  finally{$('send').disabled=false; document.body.dataset.ready='true';}
}
function renderHistory(){
  $('history').innerHTML=history.map((item,i)=>`<button data-history="${i}"><span class="method">${item.method}</span> <strong>${item.status}</strong><br>${esc(item.route)}</button>`).join('');
  $('history').querySelectorAll('button').forEach(b=>b.onclick=()=>{const item=history[Number(b.dataset.history)];$('method').value=item.method;$('route').value=item.route;$('body').value=item.body;render(item.data,item.status);$('status').textContent=item.status+' / from session';});
}
async function loadLogs(){
  try {const r=await fetch('/v0/'+logKind);const d=await r.json();
    if(logKind==='answers') $('log-content').innerHTML=d.answers?.length?`<table><thead><tr><th>Answer</th><th>Time</th><th>Request</th><th>Entry / verdict</th></tr></thead><tbody>${d.answers.map(a=>`<tr><td>${esc(a.answer_id)}</td><td>${esc(a.at)}</td><td>${esc(a.kind)}</td><td>${esc(a.entry_id)} ${esc(a.verdict||'')}</td></tr>`).join('')}</tbody></table>`:'<p>No answers yet. Send a lookup or a check.</p>';
    else $('log-content').innerHTML=`<h3>Misses</h3>${d.misses?.length?`<table><thead><tr><th>Demand</th><th>Time</th><th>Query</th></tr></thead><tbody>${d.misses.map(m=>`<tr><td>${esc(m.miss_id)}</td><td>${esc(m.at)}</td><td>${esc(JSON.stringify(m.query))}</td></tr>`).join('')}</tbody></table>`:'<p>No misses yet. Look up a specification to search the library.</p>'}<h3>Requests by key</h3>${(d.by_key||[]).map(k=>`<p class="entry-meta">${esc(k.count)} request(s): ${esc(k.key)}</p>`).join('')}`;
  }catch{$('log-content').textContent='The server log could not be loaded. Use Refresh logs to try again.';}
}
$('preset').onchange=()=>setPreset($('preset').value); $('send').onclick=send;
$('structured').onclick=()=>{$('result').hidden=false;$('json').hidden=true;$('structured').setAttribute('aria-pressed','true');$('raw').setAttribute('aria-pressed','false');};
$('raw').onclick=()=>{$('result').hidden=true;$('json').hidden=false;$('raw').setAttribute('aria-pressed','true');$('structured').setAttribute('aria-pressed','false');};
$('demand').onclick=()=>{logKind='demand';loadLogs();};$('answers').onclick=()=>{logKind='answers';loadLogs();};$('refresh').onclick=loadLogs;
(async()=>{try{[checker,catalog]=await Promise.all(['/v0/catalog/vf.contrast-2x2','/v0/catalog'].map(async path=>{const r=await fetch(path);if(!r.ok)throw new Error('Cannot load presets');return r.json();}));const state=new URLSearchParams(location.search).get('state') || 'catalog';logKind=state==='answers'?'answers':'demand';setPreset(state);await send();if(state==='demand'||state==='answers')$('log-content').scrollIntoView();}catch{$('status').textContent='Cannot load presets. Check the API connection.';document.body.dataset.ready='true';}})();
