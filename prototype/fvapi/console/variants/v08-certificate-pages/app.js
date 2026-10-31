const page = document.querySelector('#page');
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const api = async (path, body) => {
  const response = await fetch('/v0/' + path, body === undefined ? {} : {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
  return {status:response.status, data:await response.json()};
};
const label = (type, id='Library edition / API v0') => `<div class="document-label"><span>fvapi / ${esc(type)}</span><span>${esc(id)}</span></div>`;
const stamp = (text, warn=false) => `<span class="stamp ${warn?'warn':''}">${esc(text)}</span>`;
const status = replay => stamp(replay === 'real' ? 'Runnable replay' : 'Recorded, not re-run', replay !== 'real');
const meta = rows => `<dl class="meta">${rows.map(([k,v])=>`<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl>`;
const code = text => `<pre>${esc(text)}</pre>`;
const error = data => `<div class="note"><strong>${esc(data.error || 'Request failed')}</strong><p>${esc(data.detail || 'Try the request again.')}</p></div>`;
let catalog = [];

function entryDocument(entry, heading=true) {
  return `${heading ? label('Library datasheet',entry.id)+`<h1>${esc(entry.title)}</h1>`:''}${status(entry.replay.status)}
    ${entry.replay.status !== 'real' ? '<div class="note"><strong>Not re-run by fvapi.</strong><p>This is a recorded prototype stub. It is not evidence of a new replay. Fetch the files and check them yourself.</p></div>' : ''}
    <blockquote class="claim">${esc(entry.claim)}</blockquote>
    ${meta([['Entry',entry.id],['Subject',entry.subject.name+' / '+entry.subject.version],['Kind',entry.kind],['Toolchain',entry.toolchain],['Dependencies',entry.requires.join(', ')]])}
    <h2>Exact statements</h2><p>Read these statements. Confirm that they express the result you need.</p>
    ${entry.statements.map(s=>`<p class="statement">${esc(s.name)}<br>${esc(s.file)}:${esc(s.line)}</p>${code(s.text)}`).join('')}
    <h2>What you must trust</h2><p>The Lean kernel, the toolchain and the axioms below are part of the trust boundary. A server answer does not replace your own replay.</p>${code(entry.replay.expect_axioms.join('\n'))}
    <h2>Check it yourself</h2><ol><li>Download the bundle. Compare each file with its SHA-256 below.</li><li>Use the specified toolchain. Read the statements at the listed file locations.</li><li>Run the replay command in the unpacked bundle. Check the reported axioms.</li></ol>
    ${code(entry.replay.command)}<button class="secondary" id="copy-command">Copy replay command</button><p class="statement">${esc(entry.replay.note)}</p>
    ${entry.replay.transcript ? `<h3>Recorded transcript</h3>${code(entry.replay.transcript)}`:''}
    <h2>File manifest</h2>${entry.closure.map(f=>`<div class="file"><strong>${esc(f.path)}</strong> <small>${esc(f.bytes)} bytes</small><span class="hash">SHA-256 ${esc(f.sha256)}</span></div>`).join('')}
    ${entry.subject.artifact ? `<h3>Subject artifact</h3>${meta(Object.entries(entry.subject.artifact))}`:''}
    <h2>Licence and source</h2><p>${esc(entry.licence.spdx)}</p>${entry.licence.third_party.length ? entry.licence.third_party.map(n=>`<p>${esc(n.name)}: ${esc(n.spdx)}<br>${esc(n.source)}</p>`).join(''):'<p>No third-party notices are listed in this entry.</p>'}
    ${meta([['Repository',entry.source.repo],['Commit',entry.source.commit],['Source files',entry.source.paths.join('\n')]])}
    <div class="actions"><a class="button" href="/v0/bundles/${encodeURIComponent(entry.id)}.tar.gz">Download proof bundle</a><a class="button" href="#check:${encodeURIComponent(entry.id)}">Run check on input</a></div>`;
}
function wireCopy(entry) {
  const button = document.querySelector('#copy-command');
  if(button) button.onclick=async()=>{try{await navigator.clipboard.writeText(entry.replay.command);button.textContent='Replay command copied';}catch{button.textContent='Select the command above to copy it';}};
}
async function contents() {
  catalog=(await api('catalog')).data.entries;
  page.innerHTML=label('Contents')+'<h1>Library documents</h1><p class="intro">Proofs, counterexamples and checkers. Open a datasheet to read its claim and the evidence you can replay.</p><p class="statement">Every result comes with its own trust boundary.</p><div class="contents">'+catalog.map(e=>`<article><div><small>${esc(e.id)} / ${esc(e.kind)}</small><h2><a href="#entry:${encodeURIComponent(e.id)}">${esc(e.title)}</a></h2><p>${esc(e.claim)}</p></div><aside>${status(e.replay_status)}<small>${esc(e.licence_spdx)}</small></aside></article>`).join('')+'</div>';
}
async function showEntry(id) {
  const result=await api('catalog/'+encodeURIComponent(id));
  if(result.status!==200){page.innerHTML=label('Unavailable datasheet',id)+'<h1>Document not available</h1>'+error(result.data)+'<p>The catalog summary is available, but this prototype has no full datasheet for this entry. Open another document from the contents.</p><a href="#catalog">Return to contents</a>';return;}
  page.innerHTML=entryDocument(result.data);wireCopy(result.data);
}
async function lookup(auto) {
  page.innerHTML=label('Lookup request')+'<h1>Request a library answer</h1><p class="intro">Match an entry by its identifier, artifact hash or exact statement. A miss is recorded as demand.</p><form class="request" id="lookup"><h2>Request slip</h2><label for="query-key">Match by</label><select id="query-key"><option value="spec_id">Entry identifier</option><option value="artifact_sha256">Artifact SHA-256</option><option value="statement">Exact statement</option></select><label for="query-value">Value to match</label><input id="query-value" value="vf.contrast-2x2" required><button>Look up</button></form><div id="answer"></div>';
  const submit=async()=>{
    const key=document.querySelector('#query-key').value,value=document.querySelector('#query-value').value;
    const r=await api('lookup',{[key]:value});const out=document.querySelector('#answer');
    if(r.status===404){out.innerHTML=`<section class="result">${label('Demand receipt',r.data.miss_id)}<h2>No matching library document</h2>${stamp(r.data.logged?'Logged as demand':'Demand not confirmed',true)}<p>${esc(r.data.detail)}</p><p>Try a different identifier, artifact hash or statement.</p>${code(JSON.stringify(r.data.query,null,2))}<a href="#demand">Open the demand register</a></section>`;return;}
    if(r.status!==200){out.innerHTML=error(r.data);return;}
    out.innerHTML=`<section class="result">${label('Answer certificate',r.data.answer_id)}<h2>Library match found</h2>${meta([['Entry',r.data.entry_id],['Matched on',r.data.matched_on]])}<p>This certificate records a library match. It does not certify an independent replay.</p>${entryDocument(r.data.entry,false)}</section>`;wireCopy(r.data.entry);
  };
  document.querySelector('#lookup').onsubmit=e=>{e.preventDefault();submit().catch(fail);};
  if(auto){if(auto==='miss')document.querySelector('#query-value').value='no.match';await submit();}
}
async function check(id='vf.contrast-2x2', auto) {
  const r=await api('catalog/'+encodeURIComponent(id));const entry=r.data;
  page.innerHTML=label('Check request',id)+'<h1>Check an input</h1><p class="intro">Submit your input to a proved checker. Keep the returned certificate and re-run the check locally.</p><form class="request" id="check-form"><h2>Input document</h2><label for="check-id">Entry identifier</label><input id="check-id" value="'+esc(id)+'"><label for="input">Input JSON</label><textarea id="input" spellcheck="false">'+esc(JSON.stringify(entry.check?.example_input || {},null,2))+'</textarea><button>Run check</button> <button type="button" class="secondary" id="change-weight">Change one weight</button></form><div id="answer"></div>';
  document.querySelector('#change-weight').onclick=()=>{try{const v=JSON.parse(document.querySelector('#input').value);if(v.rows)v.rows[1].weights[0]+=1;document.querySelector('#input').value=JSON.stringify(v,null,2);}catch{document.querySelector('#answer').innerHTML=error({error:'Invalid JSON',detail:'Correct the input JSON, then run the check.'});}};
  const submit=async()=>{
    let input;try{input=JSON.parse(document.querySelector('#input').value);}catch{document.querySelector('#answer').innerHTML=error({error:'Invalid JSON',detail:'Correct the input JSON, then run the check.'});return;}
    const id=document.querySelector('#check-id').value;const result=await api('checks/'+encodeURIComponent(id),input),d=result.data;
    document.querySelector('#answer').innerHTML=result.status!==200 ? `<section class="result">${label('Check notice')}<h2>No runnable checker</h2>${error(d)}<p>Choose a checker from the contents. A proof-only document cannot check caller input.</p></section>` : `<section class="result">${label('Check certificate',d.answer_id)}<h2>${d.verdict==='accept'?'Input accepted':'Input rejected'}</h2>${stamp(d.verdict==='accept'?'Accepted by the checker':'Rejected by the checker',d.verdict!=='accept')}<p>${d.verdict==='accept'?'The submitted input passed the server checker. Re-run it locally before you rely on this result.':'The submitted input did not pass. Correct the input and run the check again.'}</p>${meta([['Entry',d.entry_id],['Run on',d.ran_on],['Elapsed',d.elapsed_ms+' ms'],['Exit code',d.exit_code],['Input SHA-256',d.input_sha256]])}<h3>Checker output</h3>${code(JSON.stringify(d.output,null,2))}<h3>Check it yourself</h3>${code(d.recheck.command)}<a href="${esc(d.recheck.bundle)}">Download the proof bundle</a></section>`;
  };
  document.querySelector('#check-form').onsubmit=e=>{e.preventDefault();submit().catch(fail);};
  if(auto==='reject')document.querySelector('#change-weight').click();
  if(auto)await submit();
}
async function register(kind) {
  const d=(await api(kind)).data;
  if(kind==='demand')page.innerHTML=label('Demand register')+'<h1>Unmatched requests</h1><p class="intro">These queries found no library match. Demand is recorded; single requests do not start agent work.</p><h2>Demand by key</h2>'+(!d.by_key.length?'<p>There is no recorded demand. Run a lookup to look for a library entry.</p>':`<table><thead><tr><th>Query key</th><th>Count</th></tr></thead><tbody>${d.by_key.map(x=>`<tr><td class="query">${esc(x.key)}</td><td>${esc(x.count)}</td></tr>`).join('')}</tbody></table>`)+`<h2>Request receipts</h2>${d.misses.map(m=>`<div class="file"><strong>${esc(m.miss_id)}</strong> / ${esc(m.at)}${code(JSON.stringify(m.query,null,2))}</div>`).join('')}`;
  else page.innerHTML=label('Answer register')+'<h1>Issued answers</h1><p class="intro">A record of lookups and input checks. Each answer identifies the library entry that supplied it.</p><table><thead><tr><th>Answer / time</th><th>Entry</th><th>Outcome</th></tr></thead><tbody>'+d.answers.map(a=>`<tr><td>${esc(a.answer_id)}<br><small>${esc(a.at)}</small></td><td><a href="#entry:${encodeURIComponent(a.entry_id)}">${esc(a.entry_id)}</a></td><td>${esc(a.kind)}${a.verdict?' / '+esc(a.verdict):''}</td></tr>`).join('')+'</tbody></table>'+(d.answers.length?'':'<p>There are no answers yet. Look up an entry or run a check.</p>');
}
function fail(e){page.innerHTML=label('Connection notice')+'<h1>The document could not be opened</h1><p>Check the API connection, then reload this page.</p>'+code(e.message);}
async function route(){
  page.removeAttribute('data-ready');
  const [name,id]=(location.hash.slice(1)||'catalog').split(':');
  document.querySelectorAll('nav a').forEach(a=>a.setAttribute('aria-current',a.hash.slice(1)===name?'page':'false'));
  try{
    if(name==='entry'||name==='recorded')await showEntry(decodeURIComponent(id||(name==='recorded'?'fva.glm-iround':'vf.contrast-2x2')));
    else if(name.startsWith('lookup'))await lookup(name==='lookup-hit'?'hit':name==='lookup-miss'?'miss':null);
    else if(name.startsWith('check'))await check(id?decodeURIComponent(id):name==='check-409'?'fva.glm-iround':'vf.contrast-2x2',name==='check-accept'?'accept':name==='check-reject'?'reject':name==='check-409'?'409':null);
    else if(name==='demand'||name==='answers')await register(name);
    else await contents();
  }catch(e){fail(e);}page.dataset.ready='true';
}
document.querySelector('#print').onclick=()=>window.print();window.addEventListener('hashchange',route);route();
