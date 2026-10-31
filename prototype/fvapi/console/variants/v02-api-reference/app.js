const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pretty = value => JSON.stringify(value, null, 2);
const code = value => `<pre>${esc(value)}</pre>`;
const id = 'vf.contrast-2x2';
let method = 'GET', current = 'catalog', snippetMode = 'curl', revision = 0;
const routes = {
  catalog: ['GET','/v0/catalog','Browse the catalog','Find a proved checker, a version proof, a refutation or a relation. Open an entry to inspect exactly what it proves.'],
  entry: ['GET',`/v0/catalog/${id}`,'Read a complete entry','Read the statement before you use the result. The delivered closure and replay command let you check it independently.'],
  recorded: ['GET','/v0/catalog/fva.glm-iround','Inspect a recorded entry','A recorded replay is evidence from an earlier run. It is not a verification performed by fvapi.'],
  'lookup-hit': ['POST','/v0/lookup','Look up a result','Match a specification ID, an artifact SHA-256 or the exact statement text. A hit returns the full entry and its bundle location.'],
  'lookup-miss': ['POST','/v0/lookup','Look up a result','A missing result is logged as demand. No language model runs to answer the request.'],
  'check-accept': ['POST',`/v0/checks/${id}`,'Run a proved checker','Send your own input to a runnable checker. A reject is a successful HTTP response with a negative checker verdict.'],
  'check-reject': ['POST',`/v0/checks/${id}`,'Run a proved checker','This example changes one weight. Edit the JSON, then run the check again.'],
  'check-409': ['POST','/v0/checks/fva.glm-iround','Run a proved checker','Not every library entry has a checker. Version proofs cannot accept caller input.'],
  demand: ['GET','/v0/demand','Read the demand log','Inspect missed requests and their counts by lookup key. These requests show where the library has no answer.'],
  answers: ['GET','/v0/answers','Read the answer log','Inspect the results returned by lookups and checks, with their answer IDs.']
};
function snippets() {
  const path = $('path').value;
  let body = $('body').value;
  const safe = s => "'" + s.replace(/'/g, "'\\''") + "'";
  let curl = `curl ${safe(location.origin + path)}`;
  if (method === 'POST') curl += ` \\\n  -H 'Content-Type: application/json' \\\n  -d ${safe(body)}`;
  const target = path.split('/').pop();
  let cli = path === '/v0/catalog' ? 'fvapi catalog' : path.startsWith('/v0/catalog/') ? `fvapi show ${target}` : path.startsWith('/v0/checks/') ? `# Save the JSON body as input.json\nfvapi check ${target} input.json --recheck` : '# No CLI command for this log route. Use curl.';
  if (path === '/v0/lookup') {
    try { const q = JSON.parse(body); cli = `fvapi lookup ${q.spec_id ? '--spec ' + safe(q.spec_id) : q.artifact_sha256 ? '--sha256 ' + safe(q.artifact_sha256) : '--statement ' + safe(q.statement || '')}`; } catch { cli = '# Enter valid JSON to generate the command.'; }
  }
  cli = cli.replace(/fvapi /g, `fvapi --api ${safe(location.origin)} `);
  $('snippet').textContent = snippetMode === 'curl' ? curl : cli;
}
function entry(e) {
  const recorded = e.replay.status === 'recorded';
  return `<h2 class="entry-title">${esc(e.title)}</h2><span class="tag">${esc(e.kind)}</span><code>${esc(e.id)}</code><p class="claim">${esc(e.claim)}</p><div class="note"><strong>${recorded ? 'Recorded replay — not re-run by fvapi' : 'Replay available — check it yourself'}</strong><p>${esc(e.replay.note)}</p></div><h3>Statements to verify</h3>${e.statements.map(s => `<p class="meta">${esc(s.name)}<br>${esc(s.file)}:${esc(s.line)}</p>${code(s.text)}`).join('')}<h3>Delivered closure</h3><ul class="files">${e.closure.map(f => `<li><strong>${esc(f.path)}</strong> <span class="meta">${esc(f.bytes)} bytes</span><span class="hash">SHA-256 ${esc(f.sha256)}</span></li>`).join('')}</ul><div class="actions"><a href="/v0/bundles/${encodeURIComponent(e.id)}.tar.gz">Download bundle</a><a href="#${recorded ? 'check-409' : 'check-accept'}">Try the checker</a></div><h3>Replay command</h3>${code(e.replay.command)}<button class="small-button" id="copy-replay">Copy replay command</button><h3>Expected axioms</h3>${code(e.replay.expect_axioms.join('\n') || 'None')}<h3>Toolchain and dependencies</h3><p>${esc(e.toolchain)}<br>${esc(e.requires.join(', '))}</p><h3>Licence and third-party notices</h3><p>${esc(e.licence.spdx)}</p>${e.licence.third_party.length ? e.licence.third_party.map(n => `<p>${esc(n.name)}: ${esc(n.spdx)}<br>${esc(n.source)}</p>`).join('') : '<p>No third-party notices in this entry.</p>'}<h3>Source</h3><p>${esc(e.source.repo)}<br>Commit <code>${esc(e.source.commit)}</code></p>${code(e.source.paths.join('\n'))}${e.replay.transcript ? '<h3>Earlier replay transcript</h3>' + code(e.replay.transcript) : ''}`;
}
function render(data, status) {
  if (data.entries) return `<p class="meta">${data.entries.length} entries returned</p>${data.entries.map(e => `<article class="catalog-item"><span class="tag">${esc(e.kind)}</span><code>${esc(e.id)}</code><h3><a href="#entry/${encodeURIComponent(e.id)}">${esc(e.title)}</a></h3><p>${esc(e.claim)}</p><span class="${e.replay_status === 'recorded' ? 'recorded' : 'meta'}">${e.replay_status === 'recorded' ? 'Recorded — not re-run by fvapi' : 'Real replay'}</span></article>`).join('')}`;
  if (data.statements) return entry(data);
  if (data.entry) return `<p><strong>Match found</strong> on ${esc(data.matched_on)}<br><span class="meta">Answer ${esc(data.answer_id)}</span></p>${entry(data.entry)}`;
  if (data.verdict) return `<p class="verdict ${data.verdict === 'reject' ? 'negative' : ''}">${data.verdict === 'accept' ? 'Accepted' : 'Rejected'}</p><p>${data.verdict === 'accept' ? 'The input passes the checker. Re-run it locally before you rely on this result.' : 'The input does not pass the checker. Correct the weights and run the check again.'}</p><div class="detail-grid"><p>Exit code <strong>${esc(data.exit_code)}</strong></p><p>Elapsed <strong>${esc(data.elapsed_ms)} ms</strong></p></div>${code(pretty(data.output))}<h3>Re-check locally</h3>${code(data.recheck.command)}<p class="meta">Answer ${esc(data.answer_id)}<br>Ran on ${esc(data.ran_on)}</p>`;
  if (data.misses) return `<h3>Misses (${data.misses.length})</h3>${data.misses.map(m => `<div class="log-row"><strong>${esc(m.miss_id)}</strong><p class="meta">${esc(m.at)}</p>${code(pretty(m.query))}</div>`).join('') || '<p>No misses yet. Run a lookup to see demand here.</p>'}<h3>Counts by lookup key</h3>${data.by_key.map(k => `<div class="log-row"><strong>${esc(k.count)} request${k.count === 1 ? '' : 's'}</strong><br><code>${esc(k.key)}</code></div>`).join('')}`;
  if (data.answers) return data.answers.map(a => `<div class="log-row"><span class="tag">${esc(a.kind)}</span><strong>${esc(a.answer_id)}</strong><p><code>${esc(a.entry_id)}</code>${a.verdict ? '<br>Verdict: ' + esc(a.verdict) : ''}</p><p class="meta">${esc(a.at)}</p></div>`).join('') || '<p>No answers yet. Run a lookup or a check.</p>';
  if (status === 404 && current.startsWith('lookup')) return `<div class="note"><strong>No match. Logged as demand.</strong><p>The library has no matching result. Check the query, or inspect the demand log.</p></div><a href="#demand">Read the demand log</a>${code(pretty(data))}`;
  if (status === 409) return `<div class="note"><strong>This entry has no runnable checker.</strong><p>Open its proof entry, or choose a catalog entry labelled checker.</p></div><a href="#catalog">Browse checkers in the catalog</a>`;
  return code(pretty(data));
}
async function send() {
  const token = revision;
  try {
    let body;
    if (method === 'POST') body = JSON.stringify(JSON.parse($('body').value));
    const path = $('path').value;
    if (!path.startsWith('/v0/') || path.startsWith('//')) throw new Error('Use an API path that starts with /v0/.');
    $('status').textContent = 'Sending…';
    const res = await fetch(path, {method, ...(body ? {headers:{'Content-Type':'application/json'}, body} : {})});
    const data = await res.json();
    if (token !== revision) return;
    $('status').textContent = `HTTP ${res.status}`;
    $('raw-status').textContent = `${res.status}`;
    $('raw').textContent = pretty(data);
    $('result').innerHTML = render(data, res.status);
    const button = $('copy-replay');
    if (button) button.onclick = () => copy((data.entry || data).replay.command, button);
    document.body.dataset.ready = 'true';
  } catch (error) {
    if (token !== revision) return;
    $('status').textContent = 'Request failed';
    $('result').textContent = `${error.message} Correct the request and send it again.`;
    document.body.dataset.ready = 'true';
  }
  snippets();
}
async function copy(text, button) {
  try { await navigator.clipboard.writeText(text); button.textContent = 'Copied'; } catch { button.textContent = 'Select and copy the command'; }
}
async function navigate() {
  revision++;
  const token = revision;
  document.body.dataset.ready = 'false';
  const hash = location.hash.slice(1) || 'catalog';
  const [state, selectedId] = hash.split('/');
  current = routes[state] ? state : 'catalog';
  const [verb, path, title, intro] = routes[current];
  method = verb;
  $('method').textContent = verb;
  $('path').value = current === 'entry' && selectedId ? '/v0/catalog/' + encodeURIComponent(decodeURIComponent(selectedId)) : path;
  $('route').textContent = $('path').value;
  $('title').textContent = title;
  $('intro').textContent = intro;
  $('body-wrap').hidden = method === 'GET';
  $('doc').innerHTML = current.startsWith('check') ? '<div class="actions"><a href="#check-accept">Example input</a><a href="#check-reject">One wrong weight</a><a href="#check-409">No checker</a></div>' : current.startsWith('lookup') ? '<div class="actions"><a href="#lookup-hit">Example hit</a><a href="#lookup-miss">Example miss</a></div>' : '';
  for (const a of document.querySelectorAll('nav a')) {
    const active = a.hash === '#' + current || (current.startsWith('check') && a.hash === '#check-accept') || (current.startsWith('lookup') && a.hash === '#lookup-hit');
    if (active) a.setAttribute('aria-current','page'); else a.removeAttribute('aria-current');
  }
  $('result').textContent = 'Loading response…';
  if (current.startsWith('check')) {
    const e = await fetch('/v0/catalog/' + id).then(r => r.json());
    if (token !== revision) return;
    const input = e.check.example_input;
    if (current === 'check-reject') input.rows[0].weights[0] += 1;
    $('body').value = pretty(input);
  } else if (current.startsWith('lookup')) $('body').value = pretty({spec_id: current === 'lookup-hit' ? id : 'example.missing-proof'});
  snippets();
  await send();
}
$('request').onsubmit = e => {e.preventDefault(); $('route').textContent = $('path').value; send();};
$('path').oninput = snippets;
$('body').oninput = snippets;
for (const mode of ['curl','cli']) $(mode + '-tab').onclick = () => {snippetMode = mode; for (const m of ['curl','cli']) $(m + '-tab').classList.toggle('selected',m === mode); snippets();};
$('copy').onclick = () => copy($('snippet').textContent, $('copy'));
window.addEventListener('hashchange',navigate);
navigate();
