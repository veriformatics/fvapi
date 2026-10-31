const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const pretty = value => JSON.stringify(value, null, 2);
const lines = [['checker','C','#004f98','Checker'],['version-proof','V','#915cac','Version proof'],['refutation','R','#b52e39','Refutation'],['relation','L','#093220','Relation']];
let entries = [], full = [];
async function api(path, body) {
  const response = await fetch('/v0/' + path, body === undefined ? {} : {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  return {status:response.status, data:await response.json()};
}
function map() {
  let svg = '<svg viewBox="0 0 780 395" role="img" aria-labelledby="map-desc"><title id="map-desc">Library transit map. Use the station index below to open each entry.</title>';
  const requirements = full.flatMap(e=>e.requires||[]);
  const shared = new Set(requirements.filter((r,i)=>requirements.indexOf(r)!==i));
  lines.forEach(([kind,letter,color,label], i) => {
    const y = 55 + i * 90, stops = entries.filter(e => e.kind === kind);
    svg += `<path d="M 40 ${y} H 190 L 220 ${y+25} H 730" fill="none" stroke="${color}" stroke-width="9" ${stops.length ? '' : 'stroke-dasharray="12 7"'}/><rect x="10" y="${y-18}" width="35" height="35" rx="17" fill="${color}"/><text x="27" y="${y+5}" text-anchor="middle" style="fill:white;font-weight:bold">${letter}</text>`;
    if (!stops.length) svg += `<text x="280" y="${y+9}">No ${esc(label.toLowerCase())} stations yet</text>`;
    stops.forEach((e,j) => {
      const x = 305 + j * Math.min(150,350/Math.max(stops.length-1,1));
      svg += `<a href="?state=entry&amp;id=${encodeURIComponent(e.id)}"><circle cx="${x}" cy="${y+25}" r="8" fill="white" stroke="${color}" stroke-width="4"/><text class="station-name" x="${x-12}" y="${y-4}">${esc(e.id)}</text></a>`;
    });
    const reqs = [...new Set(full.filter(e=>e.kind===kind).flatMap(e=>e.requires||[]))];
    if (reqs.length) svg += `<circle cx="160" cy="${y}" r="11" fill="white" stroke="#17334a" stroke-width="3"/>${reqs.some(r=>shared.has(r))?`<circle cx="160" cy="${y}" r="5" fill="white" stroke="#17334a" stroke-width="2"/>`:''}<text x="75" y="${y+33}" style="font-size:12px">${esc(reqs.join(', '))}</text>`;
  });
  $('map').innerHTML = svg + '</svg>';
  $('count').textContent = `${entries.length} stations / 4 lines`;
  $('stations').innerHTML = entries.map(e => {
    const line = lines.find(l=>l[0]===e.kind);
    return `<tr><td style="color:${line?.[2]||'#17334a'}"><strong>${esc(line?.[1])}</strong> ${esc(line?.[3]||e.kind)}</td><td><a href="?state=entry&id=${encodeURIComponent(e.id)}">${esc(e.title)}</a><br><small>${esc(e.id)}</small></td><td><span class="status">${e.replay_status==='recorded'?'Recorded: not re-run':'Real replay'}</span></td></tr>`;
  }).join('');
  $('check-id').innerHTML = entries.map(e=>`<option value="${esc(e.id)}">${esc(e.id)}</option>`).join('');
}
function renderEntry(e) {
  $('detail').hidden = false;
  const recorded = e.replay?.status === 'recorded';
  $('detail').innerHTML = `<p>${esc(e.kind)} station / ${esc(e.id)}</p><h2>${esc(e.title)}</h2>${recorded?'<div class="warning"><strong>Recorded stub: not re-run by fvapi.</strong><p>This transcript comes from an earlier run. It is not a fresh verification of this entry.</p></div>':'<p class="status">Real replay available</p>'}<p class="claim">${esc(e.claim)}</p><div class="actions"><a class="button" href="/v0/bundles/${encodeURIComponent(e.id)}.tar.gz">Download verification bundle</a><a href="?state=check&id=${encodeURIComponent(e.id)}">Run check on this station</a></div><h3>Statements to match</h3>${(e.statements||[]).map(s=>`<p><strong>${esc(s.name)}</strong><br>${esc(s.file)}:${esc(s.line)}</p><pre>${esc(s.text)}</pre>`).join('')}<h3>Interchanges and toolchain</h3><p>${esc((e.requires||[]).join(', ')||'No requirements listed')}<br>${esc(e.toolchain)}</p><h3>Closure files and SHA-256</h3>${(e.closure||[]).map(f=>`<div class="closure"><strong>${esc(f.path)} (${esc(f.bytes)} bytes)</strong><code>${esc(f.sha256)}</code></div>`).join('')}<h3>Replay the route yourself</h3><pre id="command">${esc(e.replay?.command)}</pre><button type="button" id="copy">Copy replay command</button><p>${esc(e.replay?.note)}</p><h3>Expected axioms</h3><pre>${esc((e.replay?.expect_axioms||[]).join('\n')||'None listed')}</pre>${e.replay?.transcript?`<h3>Recorded transcript</h3><pre>${esc(e.replay.transcript)}</pre>`:''}<h3>Licence and third-party notices</h3><p>${esc(e.licence?.spdx)}</p>${(e.licence?.third_party||[]).length?(e.licence.third_party.map(t=>`<p>${esc(t.name)} / ${esc(t.spdx)}<br>${esc(t.source)}</p>`).join('')):'<p>No third-party notices listed.</p>'}<h3>Source</h3><p>${esc(e.source?.repo)}<br>Commit: <code>${esc(e.source?.commit)}</code></p><pre>${esc((e.source?.paths||[]).join('\n'))}</pre><h3>Subject</h3><pre>${esc(pretty(e.subject))}</pre>`;
  $('copy').onclick = async () => {try {await navigator.clipboard.writeText(e.replay.command);$('copy').textContent='Command copied';} catch {$('copy').textContent='Select the command above to copy it';}};
}
async function lookup(query) {
  const {status,data} = await api('lookup',query);
  $('journey').innerHTML = status===200?`<div class="ticket"><h3>Route found</h3><p>${esc(data.entry_id)}</p><p>Matched on ${esc(data.matched_on)}</p><p>Ticket ${esc(data.answer_id)}</p><a href="?state=entry&id=${encodeURIComponent(data.entry_id)}">Open verification bundle</a></div>`:`<div class="ticket reject"><h3>${status===404?'No route yet':'Journey not found'}</h3><p>${status===404?'Logged as demand. No proof was returned. Try another statement or artifact.':esc(data.detail)}</p><a href="?state=demand">See planned extensions</a></div>`;
  if(status===200 && data.entry) renderEntry(data.entry);
}
function example() {
  const e = full.find(e=>e.id===$('check-id').value);
  $('input').value = e?.check ? pretty(e.check.example_input) : '{}';
}
function changeWeight() {try {const input=JSON.parse($('input').value); input.rows[0].weights[0] += 1; $('input').value=pretty(input);}catch {$('ticket').textContent='Load the checker example before you change a weight.';}}
async function check() {
  let input; try {input=JSON.parse($('input').value);}catch {$('ticket').innerHTML='<p class="warning">The input is not valid JSON. Correct it and run the check again.</p>';return;}
  const {status,data}=await api('checks/'+encodeURIComponent($('check-id').value),input);
  $('ticket').innerHTML=status===200?`<div class="ticket ${data.verdict==='reject'?'reject':''}"><h3>Ticket: ${esc(data.verdict)}</h3><p>${esc(data.entry_id)} / ${esc(data.answer_id)}</p><p>Ran on ${esc(data.ran_on)} in ${esc(data.elapsed_ms)} ms. Exit code ${esc(data.exit_code)}.</p><pre>${esc(pretty(data.output))}</pre><h3>Recheck this result yourself</h3><pre>${esc(data.recheck?.command)}</pre><a href="${esc(data.recheck?.bundle)}">Download the checker bundle</a><p>The server result is a lead. Re-run the checker locally.</p></div>`:`<div class="ticket reject"><h3>${status===409?'This station has no checker':'The check did not run'}</h3><p>${esc(data.detail)}</p><p>Select a checker station to run a check.</p><small>HTTP ${status} / ${esc(data.error)}</small></div>`;
}
async function logs(kind) {
  const {data}=await api(kind); $('logs').hidden=false;
  if(kind==='demand') $('logs').innerHTML=`<h2>Planned extensions</h2><p>A dashed route marks demand, not a promised proof. These requests had no matching entry.</p><svg viewBox="0 0 780 80" role="img" aria-label="Planned library extension"><path d="M20 40 H750" stroke="#915cac" stroke-width="7" stroke-dasharray="12 10"/><circle cx="60" cy="40" r="10" fill="#f4f7fa" stroke="#915cac" stroke-width="3"/><text x="80" y="25">Unmet demand</text></svg><h3>Requests by key</h3>${(data.by_key||[]).map(row=>`<p><strong>${esc(row.count)} request(s)</strong><br><code>${esc(row.key)}</code></p>`).join('')||'<p>No demand yet. Look up a statement to start a journey.</p>'}<h3>Miss log</h3>${(data.misses||[]).map(row=>`<p>${esc(row.miss_id)} / ${esc(row.at)}</p><pre>${esc(pretty(row.query))}</pre>`).join('')}`;
  else $('logs').innerHTML=`<h2>Issued tickets</h2><p>The answer log records server lookups and checks. Keep your local replay evidence separately.</p><div class="table-wrap"><table><thead><tr><th>Ticket</th><th>Journey</th><th>Outcome</th><th>Time</th></tr></thead><tbody>${(data.answers||[]).map(row=>`<tr><td>${esc(row.answer_id)}</td><td>${esc(row.kind)}<br><a href="?state=entry&id=${encodeURIComponent(row.entry_id)}">${esc(row.entry_id)}</a></td><td>${esc(row.verdict||'Lookup hit')}</td><td>${esc(row.at)}</td></tr>`).join('')}</tbody></table></div>`;
}
async function init() {
  entries=(await api('catalog')).data.entries;
  full=(await Promise.all(entries.map(e=>api('catalog/'+encodeURIComponent(e.id))))).filter(r=>r.status===200).map(r=>r.data);
  map();
  $('lookup').onsubmit=event=>{event.preventDefault();lookup({[$('key').value]:$('query').value}).catch(showError);};
  $('check-form').onsubmit=event=>{event.preventDefault();check().catch(showError);};
  $('check-id').onchange=example; $('example').onclick=example; $('change').onclick=changeWeight;
  const params=new URLSearchParams(location.search), state=params.get('state')||'catalog', id=params.get('id');
  const target = state.startsWith('check') ? 'check' : state.startsWith('lookup') ? 'lookup' : state==='entry'||state==='recorded'||state==='mobile'?'catalog':state;
  document.querySelector(`nav a[href="?state=${target}"]`)?.setAttribute('aria-current','page');
  if(state==='entry'||state==='recorded'||state==='mobile') {
    const chosen=id||(state==='recorded'?entries.find(e=>e.replay_status==='recorded'&&full.some(f=>f.id===e.id))?.id:entries.find(e=>e.kind==='checker')?.id);
    const e=full.find(e=>e.id===chosen);
    if(e) renderEntry(e);
    else {
      const summary=entries.find(e=>e.id===chosen);
      if(!summary) throw Error('This station is not in the catalog. Choose a station from the index.');
      $('detail').hidden=false;
      $('detail').innerHTML=`<h2>${esc(summary.title)}</h2><div class="warning"><strong>${summary.replay_status==='recorded'?'Recorded stub: not re-run by fvapi.':'Full entry unavailable.'}</strong><p>This service returned the catalog summary only. Select another station to inspect its closure and replay instructions.</p></div><p class="claim">${esc(summary.claim)}</p><p>${esc(summary.kind)} / ${esc(summary.id)}</p><h3>Subject</h3><pre>${esc(pretty(summary.subject))}</pre><h3>Licence</h3><p>${esc(summary.licence_spdx)}</p>`;
    }
  }
  if(state.startsWith('lookup')) {
    $('query').value=state==='lookup-miss'?'unlisted.proof':entries.find(e=>e.kind==='checker')?.id||'';
    if(state!=='lookup') await lookup({spec_id:$('query').value});
  }
  if(state.startsWith('check')) {
    $('ride').hidden=false;
    $('check-id').value=id||(state==='check-409'?entries.find(e=>e.kind!=='checker')?.id:entries.find(e=>e.kind==='checker')?.id);
    example(); if(state==='check-reject') changeWeight(); if(state!=='check') await check();
  }
  if(state==='demand'||state==='answers') await logs(state);
  document.body.dataset.ready='true';
  if(['entry','recorded','check','check-accept','check-reject','check-409','demand','answers'].includes(state)) {
    const region=state.startsWith('check')?'ride':state==='demand'||state==='answers'?'logs':'detail';
    if(!params.has('overview')) $(region).scrollIntoView();
  }
}
function showError(error) {$('error').textContent='The request failed. Check the service connection and try again. '+error.message;document.body.dataset.ready='error';}
init().catch(showError);
