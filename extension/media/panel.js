// Vibe Studio panel frontend. Talks to the extension host via postMessage.
// @ts-nocheck
(function () {
  const vscode = acquireVsCodeApi();
  let state = { agents: [], todos: [], scripts: [], systemLog: [] };
  let tab = 'team';

  window.addEventListener('message', (event) => {
    const msg = event.data;
    if (msg && msg.type === 'state') {
      state = msg.data;
      render();
    }
  });

  const post = (type, extra = {}) => vscode.postMessage({ type, ...extra });

  function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function statusColor(s) {
    return { running: 'running', starting: 'starting', error: 'error' }[s] || '';
  }

  function render() {
    const app = document.getElementById('app');
    app.innerHTML = '';

    // Tabs
    const tabs = el('div', 'tabs');
    for (const [key, label] of [['team', 'AI Team'], ['todos', 'Todos'], ['scripts', 'Scripts'], ['api', 'API']]) {
      const t = el('div', 'tab' + (tab === key ? ' active' : ''), label);
      t.onclick = () => { tab = key; render(); };
      tabs.appendChild(t);
    }
    app.appendChild(tabs);

    // Server bar
    const bar = el('div', 'serverbar');
    const dot = el('div', 'dot ' + statusColor(state.serverState));
    const label = state.serverState === 'running'
      ? `server running (port ${state.serverPort})`
      : `server ${state.serverState}`;
    bar.appendChild(dot);
    bar.appendChild(el('span', '', label));
    const spacer = el('div', 'spacer');
    bar.appendChild(spacer);
    if (state.projectDir) {
      const start = el('button', '', 'Start');
      start.onclick = () => post('serverStart');
      const stop = el('button', '', 'Stop');
      stop.onclick = () => post('serverStop');
      bar.appendChild(start);
      bar.appendChild(stop);
    }
    const fb = el('button', '', 'freebuff');
    fb.onclick = () => post('openFreebuff');
    bar.appendChild(fb);
    app.appendChild(bar);

    const content = el('div', 'content');
    if (tab === 'team') renderTeam(content);
    else if (tab === 'todos') renderTodos(content);
    else if (tab === 'scripts') renderScripts(content);
    else renderApi(content);
    app.appendChild(content);
  }

  // --------------------------------------------------------------- AI Team
  function renderTeam(content) {
    if (!state.projectDir) {
      content.appendChild(el('div', 'empty', 'Open a workspace folder to start the AI team.'));
      return;
    }

    const add = el('div', 'card');
    add.appendChild(el('label', '', 'Add agent'));
    const nameRow = el('div', 'row');
    const name = el('input');
    name.placeholder = 'name (e.g. Architect)';
    nameRow.appendChild(name);
    const role = el('select');
    for (const [v, l] of [['engineer', 'engineer'], ['tester', 'tester'], ['coordinator', 'coordinator']]) {
      const o = el('option', '', l);
      o.value = v;
      role.appendChild(o);
    }
    nameRow.appendChild(role);
    add.appendChild(nameRow);
    const opts = el('div', 'row');
    const isMain = el('input'); isMain.type = 'checkbox';
    const l1 = el('label', '', ' main'); l1.prepend(isMain);
    const runsTerm = el('input'); runsTerm.type = 'checkbox';
    const l2 = el('label', '', ' freebuff in terminal'); l2.prepend(runsTerm);
    opts.appendChild(l1); opts.appendChild(l2);
    add.appendChild(opts);
    const btnRow = el('div', 'row');
    const addBtn = el('button', 'primary', 'Add Agent');
    addBtn.onclick = () => {
      post('addAgent', { name: name.value, role: role.value, isMain: isMain.checked, runsInTerminal: runsTerm.checked });
      name.value = '';
    };
    const stopAll = el('button', '', 'Stop All');
    stopAll.onclick = () => post('stopAll');
    btnRow.appendChild(addBtn);
    const spacer = el('div', 'spacer'); btnRow.appendChild(spacer);
    btnRow.appendChild(stopAll);
    add.appendChild(btnRow);
    content.appendChild(add);

    // Mission box
    const mission = el('div', 'card');
    mission.appendChild(el('label', '', state.agents.some((a) => a.isMain && a.runsInTerminal)
      ? 'Mission — typed into the freebuff terminal'
      : 'Mission for the main AI'));
    const mInput = el('input');
    mInput.placeholder = 'e.g. "UI is broken and server error"';
    mInput.onkeydown = (e) => {
      if (e.key === 'Enter') { post('sendMission', { text: mInput.value }); mInput.value = ''; }
    };
    mission.appendChild(mInput);
    const send = el('button', 'primary', 'Send');
    send.onclick = () => { post('sendMission', { text: mInput.value }); mInput.value = ''; };
    mission.appendChild(send);
    content.appendChild(mission);

    if (state.agents.length === 0) {
      content.appendChild(el('div', 'empty', 'No agents yet. Add one or let the auto team spawn workers when todos are queued.'));
    }
    for (const a of state.agents) {
      const card = el('div', 'card');
      const head = el('div', 'head');
      const status = el('span', 'status ' + a.status, a.status);
      const title = el('span', 'title', (a.isMain ? '★ ' : '') + a.name);
      head.appendChild(status);
      head.appendChild(title);
      if (a.runsInTerminal) head.appendChild(el('span', 'badge free', 'FREE'));
      if (a.isMain) head.appendChild(el('span', 'badge main', 'main'));
      const star = el('button', '', a.isMain ? '★' : '☆');
      star.onclick = () => post('setMain', { id: a.id });
      head.appendChild(star);
      const act = el('button', '', a.status === 'stopped' ? 'Start' : 'Stop');
      act.onclick = () => post(a.status === 'stopped' ? 'startAgent' : 'stopAgent', { id: a.id });
      head.appendChild(act);
      card.appendChild(head);
      if (a.currentTask) card.appendChild(el('div', 'muted', a.currentTask));
      card.appendChild(el('div', 'muted', a.role + (a.autoManaged ? ' · auto' : '') + (a.tasksCompleted ? ` · ${a.tasksCompleted} done` : '')));
      const log = el('div', 'log', a.log.slice(-12).map((l) => (l.isError ? '⚠ ' : '') + l.text).join('\n'));
      card.appendChild(log);
      content.appendChild(card);
    }
  }

  // ----------------------------------------------------------------- Todos
  function renderTodos(content) {
    if (!state.projectDir) {
      content.appendChild(el('div', 'empty', 'Open a workspace folder to see the shared todo list.'));
      return;
    }
    const add = el('div', 'card');
    add.appendChild(el('label', '', 'New todo'));
    const title = el('input');
    title.placeholder = 'title';
    const desc = el('input');
    desc.placeholder = 'description (optional)';
    const btn = el('button', 'primary', 'Add');
    btn.onclick = () => {
      if (title.value.trim()) { post('addTodo', { title: title.value.trim(), description: desc.value.trim() }); title.value = ''; desc.value = ''; }
    };
    add.appendChild(title);
    add.appendChild(desc);
    add.appendChild(btn);
    content.appendChild(add);

    const done = state.todos.filter((t) => t.status === 'done').length;
    content.appendChild(el('div', 'muted', `${done}/${state.todos.length} done`));

    if (state.todos.length === 0) {
      content.appendChild(el('div', 'empty', 'No todos yet. Add one and agents will pick it up.'));
    }
    for (const t of state.todos) {
      const card = el('div', 'card');
      const head = el('div', 'head');
      const toggle = el('button', '', t.status === 'done' ? '☑' : (t.status === 'in_progress' ? '◉' : '○'));
      toggle.onclick = () => post('toggleTodo', { id: t.id });
      head.appendChild(toggle);
      head.appendChild(el('span', 'title', t.title));
      const del = el('button', '', '✕');
      del.onclick = () => post('deleteTodo', { id: t.id });
      head.appendChild(del);
      card.appendChild(head);
      if (t.description) card.appendChild(el('div', 'muted', t.description));
      if (t.assignee) card.appendChild(el('div', 'status ' + (t.status === 'in_progress' ? 'busy' : 'idle'), `↦ ${t.assignee}`));
      content.appendChild(card);
    }
  }

  // --------------------------------------------------------------- Scripts
  function renderScripts(content) {
    if (!state.projectDir) {
      content.appendChild(el('div', 'empty', 'Open a workspace folder to manage run scripts.'));
      return;
    }
    const b = state.scriptBootstrap;
    if (b.needed) {
      const card = el('div', 'card');
      card.appendChild(el('div', '', 'No start.sh yet — ask the AI to write the Run/Stop/Migration scripts.'));
      if (b.bootstrapping) card.appendChild(el('div', 'muted', 'Bootstrapping… (ask the opencode server)'));
      if (b.error) card.appendChild(el('div', 'error', b.error));
      const btn = el('button', 'primary', 'Bootstrap scripts');
      btn.disabled = b.bootstrapping;
      btn.onclick = () => post('bootstrapScripts');
      card.appendChild(btn);
      if (b.log) card.appendChild(el('pre', 'response', b.log));
      content.appendChild(card);
    }

    if (state.scripts.length === 0 && !b.needed) {
      content.appendChild(el('div', 'empty', 'No scripts yet.'));
    }
    for (const s of state.scripts) {
      const card = el('div', 'card');
      const head = el('div', 'head');
      head.appendChild(el('span', 'title', s.name));
      if (s.isStandard) head.appendChild(el('span', 'badge', 'standard'));
      if (s.running) head.appendChild(el('span', 'status busy', 'running'));
      else if (s.exitCode !== null) head.appendChild(el('span', 'status ' + (s.exitCode === 0 ? 'idle' : 'error'), `exited ${s.exitCode}`));
      const run = el('button', s.running ? '' : 'primary', s.running ? 'Restart' : 'Run');
      run.onclick = () => post('runScript', { name: s.name });
      head.appendChild(run);
      const stop = el('button', '', 'Stop');
      stop.disabled = !s.running;
      stop.onclick = () => post('stopScript', { name: s.name });
      head.appendChild(stop);
      if (!s.isStandard) {
        const del = el('button', '', '✕');
        del.onclick = () => post('removeScript', { name: s.name });
        head.appendChild(del);
      }
      card.appendChild(head);
      card.appendChild(el('div', 'muted', s.command));
      if (s.logs.length) card.appendChild(el('div', 'log', s.logs.slice(-30).join('\n')));
      content.appendChild(card);
    }

    const add = el('div', 'card');
    add.appendChild(el('label', '', 'Add manual script'));
    const n = el('input'); n.placeholder = 'name';
    const c = el('input'); c.placeholder = 'command (e.g. npm run dev)';
    const btn = el('button', '', 'Add');
    btn.onclick = () => {
      if (c.value.trim()) { post('addScript', { name: n.value, command: c.value }); n.value = ''; c.value = ''; }
    };
    add.appendChild(n);
    add.appendChild(c);
    add.appendChild(btn);
    content.appendChild(add);
  }

  // ------------------------------------------------------------------- API
  function renderApi(content) {
    const card = el('div', 'card');
    const row = el('div', 'row');
    const method = el('select');
    for (const m of ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
      const o = el('option', '', m);
      o.value = m;
      method.appendChild(o);
    }
    const url = el('input');
    url.placeholder = 'http://localhost:3000/api/…';
    row.appendChild(method);
    row.appendChild(url);
    card.appendChild(row);
    const headers = el('textarea');
    headers.placeholder = 'headers (JSON, optional)';
    headers.rows = 2;
    card.appendChild(el('label', '', 'Headers'));
    card.appendChild(headers);
    const body = el('textarea');
    body.placeholder = 'request body (optional)';
    body.rows = 4;
    card.appendChild(el('label', '', 'Body'));
    card.appendChild(body);
    const btnRow = el('div', 'row');
    const send = el('button', 'primary', 'Send');
    send.disabled = state.api.sending;
    send.onclick = () => {
      let parsed = {};
      try { parsed = headers.value.trim() ? JSON.parse(headers.value) : {}; } catch { /* ignore */ }
      post('apiSend', { method: method.value, url: url.value, headers: parsed, body: body.value });
    };
    const clear = el('button', '', 'Clear');
    clear.onclick = () => { post('apiClear'); };
    btnRow.appendChild(send);
    const spacer = el('div', 'spacer'); btnRow.appendChild(spacer);
    btnRow.appendChild(clear);
    card.appendChild(btnRow);
    content.appendChild(card);

    const last = state.api.last;
    if (last) {
      const res = el('div', 'card');
      res.appendChild(el('div', 'status ' + (last.success ? 'idle' : 'error'), `${last.statusLabel} — ${last.success ? 'OK' : 'FAILURE'}`));
      if (last.body) res.appendChild(el('pre', 'response', last.body));
      if (last.error) res.appendChild(el('div', 'error', last.error));
      const report = el('button', '', 'Report to main AI');
      report.onclick = () => post('apiReport');
      res.appendChild(report);
      content.appendChild(res);
    }

    if (state.systemLog.length) {
      content.appendChild(el('h3', '', 'System log'));
      content.appendChild(el('div', 'log', state.systemLog.slice(-25).map((l) => l.text).join('\n')));
    }
  }

  render();
})();
