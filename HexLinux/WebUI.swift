#if !os(macOS)
enum WebUI {
  static let html = """
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Hex — Voice to Text</title>
  <style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;justify-content:center;padding:20px}
  .app{max-width:680px;width:100%}
  header{text-align:center;padding:24px 0;border-bottom:1px solid #21262d;margin-bottom:24px}
  header h1{font-size:24px;font-weight:600;background:linear-gradient(135deg,#58a6ff,#bc8cff);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
  header .sub{font-size:13px;color:#8b949e;margin-top:4px}
  .status-bar{display:flex;align-items:center;gap:12px;padding:14px 18px;background:#161b22;border:1px solid #21262d;border-radius:10px;margin-bottom:16px}
  .status-dot{width:10px;height:10px;border-radius:50%;background:#3fb950}
  .status-dot.recording{background:#f85149;animation:pulse 1s infinite}
  .status-dot.transcribing{background:#d29922;animation:pulse .5s infinite}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
  .status-text{font-size:14px;flex:1}
  .status-time{font-size:12px;color:#8b949e}
  .card{background:#161b22;border:1px solid #21262d;border-radius:10px;padding:18px;margin-bottom:14px}
  .card h2{font-size:16px;font-weight:600;margin-bottom:12px;color:#f0f6fc}
  button,.btn{padding:10px 20px;border:none;border-radius:8px;font-size:14px;font-weight:500;cursor:pointer;transition:all .15s}
  button:hover{filter:brightness(1.15)}
  button:active{transform:scale(.98)}
  .btn-primary{background:#238636;color:#fff;width:100%}
  .btn-danger{background:#da3633;color:#fff}
  .btn-secondary{background:#21262d;color:#c9d1d9;border:1px solid #30363d}
  .btn-small{padding:5px 12px;font-size:12px}
  .btn-recording{background:#da3633!important;animation:pulse 1s infinite}
  .result-box{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:14px;font-size:15px;line-height:1.6;min-height:60px;color:#f0f6fc;white-space:pre-wrap;word-break:break-word;margin-bottom:12px}
  .result-box:empty::after{content:'Your transcription will appear here...';color:#484f58}
  select{width:100%;padding:10px 14px;background:#0d1117;color:#c9d1d9;border:1px solid #30363d;border-radius:8px;font-size:14px;cursor:pointer}
  .progress-bar{height:8px;background:#21262d;border-radius:4px;overflow:hidden;margin:10px 0}
  .progress-fill{height:100%;background:linear-gradient(90deg,#238636,#3fb950);transition:width .3s;border-radius:4px}
  .progress-text{font-size:12px;color:#8b949e;text-align:center}
  .model-item{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;background:#0d1117;border:1px solid #21262d;border-radius:8px;margin-bottom:8px}
  .model-item.selected{border-color:#58a6ff}
  .model-name{font-size:14px;font-weight:500;flex:1}
  .model-meta{font-size:12px;color:#8b949e;display:flex;gap:12px;align-items:center}
  .model-actions{display:flex;gap:6px;margin-left:12px}
  .stars{color:#d29922;font-size:12px}
  .stars .dim{color:#30363d}
  .badge{display:inline-block;padding:2px 6px;border-radius:4px;font-size:11px;font-weight:500}
  .badge-dl{background:#1f6feb33;color:#58a6ff}
  .badge-en{background:#8957e533;color:#bc8cff}
  .badge-ml{background:#3fb95033;color:#3fb950}
  .flex-row{display:flex;gap:8px;align-items:center}
  .flex-row button{flex:1}
  .text-sm{font-size:13px;color:#8b949e}
  .mt-12{margin-top:12px}
  .error-box{background:#da363322;border:1px solid #da3633;border-radius:8px;padding:12px;color:#f85149;font-size:13px;margin-bottom:12px}
  .error-box:empty{display:none}
  .split-buttons{display:flex;gap:8px}
  .split-buttons button{flex:1}
  @media(max-width:600px){body{padding:10px}.app{max-width:100%}}
  </style>
  </head>
  <body>
  <div class="app">
  <header>
  <h1>Hex</h1>
  <div class="sub">Voice to Text · Linux Edition</div>
  </header>

  <div class="status-bar">
  <div class="status-dot" id="statusDot"></div>
  <div class="status-text" id="statusText">Ready</div>
  <div class="status-time" id="statusTime"></div>
  </div>

  <div id="errorBox" class="error-box"></div>

  <div class="card">
  <div class="result-box" id="resultBox"></div>
  <div class="split-buttons">
  <button class="btn-primary" id="recordBtn" onclick="toggleRecording()">Start Recording</button>
  <button class="btn-secondary" id="pasteBtn" onclick="pasteText()">Paste</button>
  </div>
  </div>

  <div class="card">
  <h2>Model</h2>
  <select id="modelSelect" onchange="selectModel(this.value)">
  <option value="">Loading...</option>
  </select>
  <div class="progress-bar mt-12" id="downloadProgress" style="display:none">
  <div class="progress-fill" id="downloadFill"></div>
  </div>
  <div class="progress-text" id="downloadText" style="display:none"></div>
  </div>

  <div class="card">
  <h2>Available Models</h2>
  <div id="modelList">Loading...</div>
  </div>

  <div class="card">
  <h2>Settings</h2>
  <div class="text-sm">Language (auto = detect):</div>
  <select id="langSelect" onchange="setLanguage(this.value)" style="margin-top:6px">
  <option value="">Auto-detect</option>
  <option value="en">English</option>
  <option value="fr">French</option>
  <option value="de">German</option>
  <option value="es">Spanish</option>
  <option value="it">Italian</option>
  <option value="ja">Japanese</option>
  <option value="zh">Chinese</option>
  <option value="ko">Korean</option>
  <option value="pt">Portuguese</option>
  <option value="ru">Russian</option>
  <option value="ar">Arabic</option>
  <option value="hi">Hindi</option>
  </select>
  </div>
  </div>

  <script>
  let pollTimer = null;
  let recordingStart = null;

  async function api(path, method = 'GET') {
  try {
  const r = await fetch(path, { method });
  return r.ok ? r.json() : null;
  } catch(e) { return null; }
  }

  async function poll() {
  const status = await api('/api/status');
  if (!status) return;

  document.getElementById('errorBox').textContent = status.error || '';

  if (status.isRecording) {
  document.getElementById('statusDot').className = 'status-dot recording';
  document.getElementById('statusText').textContent = 'Recording...';
  document.getElementById('recordBtn').textContent = 'Stop Recording';
  document.getElementById('recordBtn').className = 'btn-primary btn-recording';
  if (!recordingStart) recordingStart = Date.now();
  const elapsed = Math.floor((Date.now() - recordingStart) / 1000);
  document.getElementById('statusTime').textContent =
  Math.floor(elapsed/60)+':'+String(elapsed%60).padStart(2,'0');
  } else if (status.isTranscribing) {
  document.getElementById('statusDot').className = 'status-dot transcribing';
  document.getElementById('statusText').textContent = 'Transcribing...';
  document.getElementById('recordBtn').textContent = 'Transcribing...';
  document.getElementById('recordBtn').className = 'btn-primary';
  document.getElementById('recordBtn').disabled = true;
  recordingStart = null;
  document.getElementById('statusTime').textContent = '';
  } else if (status.isDownloading) {
  document.getElementById('statusDot').className = 'status-dot transcribing';
  document.getElementById('statusText').textContent = 'Downloading model...';
  document.getElementById('recordBtn').textContent = 'Start Recording';
  document.getElementById('recordBtn').className = 'btn-primary';
  document.getElementById('recordBtn').disabled = false;
  recordingStart = null;
  document.getElementById('statusTime').textContent = '';
  document.getElementById('downloadProgress').style.display = 'block';
  document.getElementById('downloadFill').style.width = (status.downloadProgress * 100) + '%';
  document.getElementById('downloadText').style.display = 'block';
  document.getElementById('downloadText').textContent = Math.floor(status.downloadProgress * 100) + '%';
  } else {
  document.getElementById('statusDot').className = 'status-dot';
  document.getElementById('statusText').textContent = 'Ready';
  document.getElementById('recordBtn').textContent = 'Start Recording';
  document.getElementById('recordBtn').className = 'btn-primary';
  document.getElementById('recordBtn').disabled = false;
  recordingStart = null;
  document.getElementById('statusTime').textContent = '';
  document.getElementById('downloadProgress').style.display = 'none';
  document.getElementById('downloadText').style.display = 'none';
  }

  if (status.lastTranscription) {
  document.getElementById('resultBox').textContent = status.lastTranscription;
  }
  }

  async function pollModels() {
  const data = await api('/api/models');
  if (!data || !data.models) return;

  const select = document.getElementById('modelSelect');
  const selected = select.value;
  select.innerHTML = '';

  let hasSelected = false;
  const list = document.getElementById('modelList');
  list.innerHTML = '';

  for (const m of data.models) {
  const opt = document.createElement('option');
  opt.value = m.name;
  opt.textContent = (m.isDownloaded ? '[✓] ' : '[ ] ') + m.displayName + ' (' + m.sizeHuman + ')';
  if (m.isSelected) { opt.selected = true; hasSelected = true; }
  select.appendChild(opt);

  const div = document.createElement('div');
  div.className = 'model-item' + (m.isSelected ? ' selected' : '');
  const starsHtml = (c, n) => '<span class="stars">' +
  '★'.repeat(n) + '<span class="dim">★</span>'.repeat(Math.max(0,c-n)) + '</span>';
  div.innerHTML = `
  <div>
  <div class="model-name">${m.displayName}</div>
  <div class="model-meta">
  <span>${m.sizeHuman}</span>
  <span class="badge ${m.englishOnly ? 'badge-en' : 'badge-ml'}">${m.englishOnly ? 'EN' : 'ML'}</span>
  ${starsHtml(5, m.speedStars)} speed
  ${starsHtml(5, m.accuracyStars)} acc
  </div>
  </div>
  <div class="model-actions">
  ${m.isDownloaded
  ? '<button class="btn-secondary btn-small" onclick="deleteModel(\\''+m.name+'\\')">Delete</button>'
  : '<button class="btn-secondary btn-small" style="background:#1f6feb;color:#fff" onclick="downloadModel(\\''+m.name+'\\')">Download</button>'}
  ${!m.isSelected ? '<button class="btn-secondary btn-small" onclick="selectModel(\\''+m.name+'\\')">Select</button>' : ''}
  </div>`;
  list.appendChild(div);
  }
  }

  async function toggleRecording() {
  const btn = document.getElementById('recordBtn');
  if (btn.textContent.includes('Stop')) {
  await api('/api/record/stop', 'POST');
  } else {
  recordingStart = Date.now();
  await api('/api/record/start', 'POST');
  }
  }

  async function pasteText() {
  await api('/api/paste', 'POST');
  }

  async function downloadModel(name) {
  await api('/api/download/' + encodeURIComponent(name), 'POST');
  document.getElementById('downloadProgress').style.display = 'block';
  document.getElementById('downloadText').style.display = 'block';
  }

  async function deleteModel(name) {
  if (confirm('Delete ' + name + '?')) {
  await api('/api/delete/' + encodeURIComponent(name), 'POST');
  setTimeout(pollModels, 1000);
  }
  }

  async function selectModel(name) {
  await api('/api/select/' + encodeURIComponent(name), 'POST');
  setTimeout(pollModels, 500);
  }

  async function setLanguage(lang) {
  // Lang is stored via settings — just a note for now
  }

  // Init
  poll();
  pollModels();
  pollTimer = setInterval(() => { poll(); pollModels(); }, 2000);
  </script>
  </body>
  </html>
  """
}
#endif
