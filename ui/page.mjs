// rabadon ui — the page. One HTML document, zero build step, zero dependency.
//
// Design law (same as the landing, index.html): color IS pipeline state, never
// decoration. blue = flowing, warm = broken, lilac = rabadon intervening,
// green = repaired/passed. Dark anthracite stage, Space Grotesk Light display,
// mono for everything that is data. Left-weighted; nothing piles up in a
// centered column.

export function page() {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>rabadon — the ledger</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400&display=swap" rel="stylesheet">
<style>
  :root{
    --stage:#0e1018; --panel:#12151f; --line:#232739;
    --ink:#eef0f7; --ink-dim:#9aa0b8;
    --flow:#5b8cff; --catch:#b98cff; --ok:#4fd39a; --break:#ff8a6b;
    --mono:"SF Mono",ui-monospace,"JetBrains Mono",Menlo,Consolas,monospace;
    --display:"Space Grotesk",Helvetica,Arial,sans-serif;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--stage);color:var(--ink);font-family:var(--mono);font-size:13px;line-height:1.5}
  a{color:inherit}

  header{display:flex;align-items:baseline;gap:24px;padding:18px 28px;border-bottom:1px solid var(--line)}
  .wordmark{font-family:var(--display);font-weight:300;font-size:22px;letter-spacing:.5px}
  .wordmark .dot{display:inline-block;width:8px;height:8px;margin-left:2px;background:var(--catch);animation:pulse 2.4s infinite}
  @keyframes pulse{0%,100%{background:var(--catch)}45%{background:var(--break)}70%{background:var(--ok)}}
  .tagline{color:var(--ink-dim);font-size:12px}
  nav{margin-left:auto;display:flex;gap:2px}
  nav button, .range button{background:none;border:1px solid var(--line);color:var(--ink-dim);font-family:var(--mono);font-size:12px;padding:5px 14px;cursor:pointer}
  nav button.on, .range button.on{color:var(--ink);border-color:var(--ink-dim)}
  .range{display:flex;gap:2px}
  #liveDot{color:var(--ok);font-size:11px;align-self:center}

  main{padding:24px 28px;max-width:1500px}

  /* the ledger strip — numbers first, each backed by spool events */
  .ledger{display:flex;gap:0;border:1px solid var(--line);margin-bottom:22px}
  .ledger .cell{padding:16px 26px;border-right:1px solid var(--line);min-width:150px}
  .ledger .cell:last-child{border-right:none}
  .ledger .n{font-family:var(--display);font-weight:300;font-size:34px;line-height:1.1}
  .ledger .l{color:var(--ink-dim);font-size:11px;margin-top:2px}
  .n.catch{color:var(--catch)} .n.ok{color:var(--ok)} .n.break{color:var(--break)} .n.flow{color:var(--flow)}

  .cols{display:grid;grid-template-columns:290px 1fr;gap:22px;align-items:start}

  h2{font-family:var(--display);font-weight:300;font-size:15px;color:var(--ink-dim);margin:0 0 10px;letter-spacing:.4px}

  .panel{border:1px solid var(--line);background:var(--panel)}

  /* projects rail */
  .proj{display:flex;justify-content:space-between;gap:8px;padding:9px 14px;border-bottom:1px solid var(--line);cursor:pointer}
  .proj:last-child{border-bottom:none}
  .proj:hover,.proj.on{background:#181c2c}
  .proj .name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .proj .k{color:var(--ink-dim);font-size:11px;flex-shrink:0}
  .proj .k b{font-weight:400}
  .proj .k .c{color:var(--catch)} .proj .k .r{color:var(--ok)}

  /* live feed */
  .feed{height:230px;overflow-y:auto;padding:10px 14px;font-size:12px}
  .feed div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .feed .t{color:#555b74} .feed .p{color:var(--ink-dim)}
  .ev-flow{color:var(--flow)} .ev-break{color:var(--break)} .ev-catch{color:var(--catch)} .ev-ok{color:var(--ok)} .ev-dim{color:var(--ink-dim)}

  /* runs */
  .run{border-bottom:1px solid var(--line)}
  .run:last-child{border-bottom:none}
  .runHead{display:flex;gap:14px;align-items:baseline;padding:10px 14px;cursor:pointer}
  .runHead:hover{background:#181c2c}
  .verdict{font-size:11px;padding:1px 8px;border:1px solid;flex-shrink:0}
  .v-PASS{color:var(--ok);border-color:var(--ok)}
  .v-LIVE{color:var(--flow);border-color:var(--flow);animation:blink 1.6s infinite}
  @keyframes blink{50%{opacity:.45}}
  .v-OPEN{color:var(--ink-dim);border-color:var(--line)}
  .v-CHECK_FAILED,.v-RUNAWAY,.v-THREW,.v-DRIFT{color:var(--break);border-color:var(--break)}
  .runHead .pipe{min-width:200px}
  .runHead .meta{color:var(--ink-dim);font-size:11px}
  .runHead .catchN{color:var(--catch);font-size:11px}
  .trace{padding:4px 14px 14px 40px;display:none}
  .run.open .trace{display:block}
  .stepRow{padding:3px 0;border-left:1px solid var(--line);padding-left:16px;position:relative}
  .stepRow:before{content:"";position:absolute;left:-3px;top:9px;width:5px;height:5px;background:var(--ink-dim)}
  .stepRow.s-ok:before{background:var(--ok)} .stepRow.s-repaired:before{background:var(--catch)}
  .stepRow.s-broke:before,.stepRow.s-blocked:before{background:var(--break)}
  .stepRow.s-running:before,.stepRow.s-repairing:before{background:var(--flow)}
  .stepRow .why{color:var(--break);font-size:12px;padding-left:14px}
  .stepRow .rep{color:var(--catch);font-size:12px;padding-left:14px}
  .stepRow .st{color:var(--ink-dim);font-size:11px;margin-left:10px}
  .stopDetail{color:var(--break);font-size:12px;margin-top:8px}
  .boundTag{color:var(--ink-dim);font-size:11px;margin-top:8px}

  /* fleet */
  table{width:100%;border-collapse:collapse}
  th{font-family:var(--display);font-weight:300;color:var(--ink-dim);text-align:left;font-size:12px;padding:8px 14px;border-bottom:1px solid var(--line)}
  td{padding:7px 14px;border-bottom:1px solid var(--line);font-size:12px}
  tr:last-child td{border-bottom:none}
  .on-g{color:var(--ok)} .off-g{color:var(--ink-dim)} .warn-g{color:var(--break)}

  .empty{color:var(--ink-dim);padding:18px 14px;font-size:12px}
  footer{color:#555b74;font-size:11px;padding:18px 28px;border-top:1px solid var(--line);margin-top:30px}
</style>
</head>
<body>
<header>
  <div class="wordmark">rabadon<span class="dot"></span></div>
  <div class="tagline">the ledger — every checked pipeline on this machine. local only, nothing leaves.</div>
  <nav>
    <button id="tabOverview" class="on">ledger</button>
    <button id="tabFleet">fleet</button>
  </nav>
  <div class="range">
    <button data-days="1">today</button>
    <button data-days="7" class="on">7d</button>
    <button data-days="30">30d</button>
  </div>
  <span id="liveDot">● live</span>
</header>

<main>
  <div id="viewOverview">
    <div class="ledger" id="ledger"></div>
    <div class="cols">
      <div>
        <h2>projects</h2>
        <div class="panel" id="projects"><div class="empty">no events in this window yet</div></div>
      </div>
      <div>
        <h2>live</h2>
        <div class="panel feed" id="feed"><div class="empty" id="feedEmpty">quiet — no events yet today. run a pipeline, a supervised session or \`rabadon do\` anywhere on this machine and it lands here the moment it happens.</div></div>
        <h2 style="margin-top:22px">runs<span id="runFilter" style="color:var(--catch)"></span></h2>
        <div class="panel" id="runs"><div class="empty">no runs in this window yet</div></div>
      </div>
    </div>
  </div>

  <div id="viewFleet" style="display:none">
    <h2>fleet — every project standing under guard</h2>
    <div class="panel"><table id="fleetTable">
      <thead><tr><th>project</th><th>rules</th><th>hooks</th><th>push gate</th><th>state</th><th>last activity</th></tr></thead>
      <tbody></tbody>
    </table></div>
  </div>
</main>

<footer id="foot">reading the local spool…</footer>

<script>
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let days = 7, projectFilter = null;

const hms = (ts) => new Date(ts).toTimeString().slice(0,8);
const ago = (ts) => {
  if (!ts) return '—';
  const m = Math.round((Date.now()-ts)/60000);
  if (m < 1) return 'just now';
  if (m < 60) return m + 'm ago';
  if (m < 60*24) return Math.round(m/60) + 'h ago';
  return Math.round(m/1440) + 'd ago';
};
const dur = (ms) => ms < 1000 ? ms+'ms' : ms < 60000 ? (ms/1000).toFixed(1)+'s' : Math.round(ms/60000)+'m';

async function loadSummary(){
  const r = await fetch('/api/summary?days='+days).then(x=>x.json());
  $('ledger').innerHTML = [
    ['flow',  r.totals.gated,     'actions gated'],
    ['catch', r.totals.blocked,   'caught before happening'],
    ['break', r.totals.checkFails,'breaks caught at the gate'],
    ['ok',    r.totals.repairsOk, 'repairs accepted'],
    ['',      r.totals.runs,      'runs'],
    ['',      r.totals.projects,  'projects'],
  ].map(([c,n,l]) => '<div class="cell"><div class="n '+c+'">'+n+'</div><div class="l">'+l+'</div></div>').join('');

  $('projects').innerHTML = r.projects.length ? r.projects.map(p =>
    '<div class="proj'+(projectFilter===p.project?' on':'')+'" data-p="'+esc(p.project)+'">'+
      '<span class="name">'+esc(p.project)+'</span>'+
      '<span class="k"><b class="c">'+(p.blocked+p.checkFails)+'</b> caught · <b class="r">'+p.repairsOk+'</b> repaired</span>'+
    '</div>').join('') : '<div class="empty">no events in this window yet</div>';
  for (const el of document.querySelectorAll('.proj')) el.onclick = () => {
    projectFilter = projectFilter === el.dataset.p ? null : el.dataset.p;
    $('runFilter').textContent = projectFilter ? ' · '+projectFilter : '';
    loadSummary(); loadRuns();
  };
  $('foot').textContent = 'spool: '+r.spoolDir+' · window: '+r.days+'d · '+
    (r.unparseable ? r.unparseable+' unparseable line(s) — counted, not hidden · ' : '')+
    'every number on this page is backed by a timestamped event on your disk.';
}

function stepRow(s){
  let html = '<div class="stepRow s-'+s.status+'">'+esc(s.name)+'<span class="st">'+s.status+'</span>';
  for (const f of s.fails) html += '<div class="why">✗ '+esc(f.check)+': '+esc(f.why)+'</div>';
  for (const rp of s.repairs) html += '<div class="rep">⟲ repair #'+rp.attempt+' '+(rp.ok?'accepted':'failed'+(rp.why?': '+esc(rp.why):''))+'</div>';
  return html + '</div>';
}

async function loadRuns(){
  const q = '/api/runs?days='+days+(projectFilter?'&project='+encodeURIComponent(projectFilter):'');
  const r = await fetch(q).then(x=>x.json());
  $('runs').innerHTML = r.runs.length ? r.runs.map((run,i) =>
    '<div class="run" id="run'+i+'">'+
      '<div class="runHead" onclick="document.getElementById(\\'run'+i+'\\').classList.toggle(\\'open\\')">'+
        '<span class="verdict v-'+esc(run.verdict)+'">'+esc(run.verdict)+'</span>'+
        '<span class="pipe">'+esc(run.pipe)+'</span>'+
        '<span class="meta">'+run.steps.length+' step(s) · '+dur(run.durMs)+' · '+ago(run.end)+'</span>'+
        ((run.counts.blocked+run.counts.checkFails)?'<span class="catchN">'+(run.counts.blocked+run.counts.checkFails)+' caught</span>':'')+
        (run.counts.repairsOk?'<span class="catchN" style="color:var(--ok)">'+run.counts.repairsOk+' repaired</span>':'')+
      '</div>'+
      '<div class="trace">'+
        run.steps.map(stepRow).join('')+
        (run.stopDetail?'<div class="stopDetail">■ '+esc(run.stopDetail)+'</div>':'')+
        (run.bound?'<div class="boundTag">bound: '+esc(Object.entries(run.bound).map(([k,v])=>k+'='+v).join(' '))+'</div>':'')+
      '</div>'+
    '</div>').join('') : '<div class="empty">no runs in this window yet</div>';
}

async function loadFleet(){
  const r = await fetch('/api/fleet').then(x=>x.json());
  document.querySelector('#fleetTable tbody').innerHTML = r.fleet.length ? r.fleet.map(p =>
    '<tr><td>'+esc(p.project)+'</td>'+
    '<td>'+p.rules+(p.disabled?' <span class="off-g">('+p.disabled+' off)</span>':'')+'</td>'+
    '<td class="'+(p.hooks?'on-g':'warn-g')+'">'+(p.hooks?'installed':'missing')+'</td>'+
    '<td class="'+(p.pushGate?'on-g':'off-g')+'">'+(p.pushGate?'armed':'—')+'</td>'+
    '<td class="'+(p.off?'off-g':'on-g')+'">'+(p.off?'paused':'guarding')+'</td>'+
    '<td class="off-g">'+ago(p.lastActivity)+'</td></tr>').join('')
    : '<tr><td colspan="6" class="empty">no guarded projects under: '+esc(r.roots.join(', '))+'</td></tr>';
}

// live feed — same render law as \`rabadon watch\`
function feedLine(e){
  const cls = { RUN_START:'ev-flow', STEP_START:'ev-flow', STEP_OK:'ev-ok', CHECK_FAIL:'ev-break',
    REPAIR_START:'ev-catch', REPAIR_OK:'ev-ok', REPAIR_FAIL:'ev-break', STOP:'ev-break', RUN_DONE:'ev-ok' }[e.ev] || 'ev-dim';
  let msg = e.ev;
  if (e.ev==='RUN_START') msg = '▶ run start '+(e.steps?('['+e.steps.join(' → ')+']'):'');
  if (e.ev==='STEP_START') msg = '→ '+e.step;
  if (e.ev==='STEP_OK') msg = '✓ '+e.step;
  if (e.ev==='CHECK_FAIL') msg = '✗ BROKE '+e.step+'  '+(e.fails||[]).map(f=>f.check+': '+f.why).join(' | ');
  if (e.ev==='REPAIR_START') msg = '⟲ repair #'+e.attempt+' '+e.step;
  if (e.ev==='REPAIR_OK') msg = '✓ repaired '+e.step;
  if (e.ev==='REPAIR_FAIL') msg = '✗ repair failed '+e.step;
  if (e.ev==='STOP') msg = '■ STOP '+e.reason+' '+(e.detail||'');
  if (e.ev==='RUN_DONE') msg = '● '+e.verdict;
  if (e.ev==='RUN_DONE' && e.verdict!=='PASS') { /* keep break color for a failed verdict */ }
  const div = document.createElement('div');
  div.innerHTML = '<span class="t">'+hms(e.ts)+'</span> <span class="p">'+esc(e.pipe)+'</span> <span class="'+cls+'">'+esc(msg)+'</span>';
  const feed = $('feed');
  const ph = $('feedEmpty'); if (ph) ph.remove();
  feed.appendChild(div);
  while (feed.children.length > 400) feed.removeChild(feed.firstChild);
  feed.scrollTop = feed.scrollHeight;
}

let refreshTimer = null;
function connectLive(){
  const es = new EventSource('/api/live');
  es.onmessage = (m) => {
    try { feedLine(JSON.parse(m.data)); } catch { return; }
    $('liveDot').style.color = 'var(--ok)';
    // fresh events change the ledger — refresh it, debounced
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(() => { loadSummary(); loadRuns(); }, 1200);
  };
  es.onerror = () => { $('liveDot').style.color = 'var(--break)'; };
}

$('tabOverview').onclick = () => { $('viewOverview').style.display=''; $('viewFleet').style.display='none'; $('tabOverview').classList.add('on'); $('tabFleet').classList.remove('on'); };
$('tabFleet').onclick = () => { $('viewOverview').style.display='none'; $('viewFleet').style.display=''; $('tabFleet').classList.add('on'); $('tabOverview').classList.remove('on'); loadFleet(); };
for (const b of document.querySelectorAll('.range button')) b.onclick = () => {
  days = Number(b.dataset.days);
  for (const x of document.querySelectorAll('.range button')) x.classList.toggle('on', x===b);
  loadSummary(); loadRuns();
};

loadSummary(); loadRuns(); connectLive();
setInterval(() => { loadSummary(); loadRuns(); }, 30000);
</script>
</body>
</html>`;
}

export default { page };
