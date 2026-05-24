'use strict';

// ============================================================
// i18n
// ============================================================
const I18N = {
  zh: {
    'app.title': '工作区工具',

    'header.add': '＋ 新工作区',
    'header.import': '导入',
    'header.export': '导出',
    'header.rules': '规则',
    'header.settings': '⚙ 设置',
    'header.lang': 'EN',

    'footer.hint': '拖动窗口到另一张卡片 = 移动 · 按住 <kbd>Ctrl</kbd> 拖动 = 复制 · <kbd>Esc</kbd> 关闭面板',

    'drawer.settings.title': '设置',
    'settings.global': '全局快捷键',
    'settings.panelHotkey': '打开管理面板',
    'settings.managerHotkey': '打开管理面板（备用）',
    'settings.reloadHotkey': '重载配置',
    'settings.undoHotkey': '撤销上一次切换',
    'settings.prevWorkspaceHotkey': '上一个工作区（默认鼠标侧键后退键）',
    'settings.nextWorkspaceHotkey': '下一个工作区（默认鼠标侧键前进键）',
    'settings.behavior': '行为',
    'settings.switchToast': '切换浮窗（屏幕中央提示）',
    'settings.trayBadge': '托盘提示徽章（显示当前工作区）',
    'settings.focusMode': '焦点模式（最小化非当前工作区窗口）',
    'settings.captureThumbnails': '捕获窗口缩略图（每窗口约 5KB）',
    'settings.previewSize': '悬停预览尺寸',
    'settings.stickyEnabled': '启用常驻窗口',
    'settings.stickyTitle': '常驻窗口列表',
    'settings.stickyDesc': '匹配这些模式的窗口在所有工作区都可见，不会被快照捕获到特定工作区。',
    'settings.stickyPlaceholder': 'ahk_exe wechat.exe   或   ahk_class TXGuiFoundation',

    'drawer.rules.title': '规则',
    'rules.blacklist': '黑名单',
    'rules.blacklistDesc': '匹配下列任一模式的窗口永远不会被快照捕获。',
    'rules.blacklistPlaceholder': 'ahk_exe somethingbad.exe',
    'rules.perApp': '每应用规则',
    'rules.perAppDesc': '覆盖特定应用的恢复行为。',
    'rules.exe': '进程 (exe)',
    'rules.maxim': '总是最大化',
    'rules.monitor': '偏好显示器',
    'rules.addRule': '添加规则',

    'recorder.title': '录制快捷键',
    'recorder.desc': '按下组合键（如 <kbd>Ctrl+Alt+W</kbd>）。鼠标支持：<kbd>中键</kbd> <kbd>侧键 XButton1/2</kbd>，以及 <kbd>修饰键+滚轮</kbd>。',
    'recorder.label': '录制快捷键 · {label}',
    'recorder.empty': '(无)',
    'button.add': '添加',
    'button.pick': '选取…',
    'button.clear': '清空',
    'button.cancel': '取消',
    'button.ok': '确定',
    'button.import': '导入',

    'picker.title': '添加活动窗口',
    'picker.desc': '选一个当前打开的窗口加进这个工作区。',

    'import.title': '导入配置',
    'import.desc': '粘贴之前导出的 JSON。会覆盖你的设置、工作区和规则。',
    'import.invalid': '无效 JSON：{err}',

    'ws.add': '＋ 新建工作区',
    'ws.empty': '暂无窗口',
    'ws.addWindow': '＋ 添加窗口',
    'ws.iconTitle': '点击更换图标',
    'ws.snapshot': '把当前所有窗口存到这个工作区',
    'ws.restore': '应用这个工作区',
    'ws.delete': '删除这个工作区',
    'ws.removeWin': '从工作区移除',
    'ws.chipRestore': '恢复',
    'ws.chipSave': '保存',
    'ws.chipTitle': '点击录制快捷键',

    'prompt.wsName': '工作区名称?',
    'prompt.wsNameDefault': '未命名',
    'prompt.snapshot': '把当前所有窗口存为初始快照？',
    'confirm.deleteWs': '确定要删除工作区 "{name}" 吗？',
    'prompt.icon': '图标（emoji 或字符）：',
    'prompt.saveIdPrompt': '存到工作区编号 (1-9)：',

    'flash.exported': '已复制到剪贴板。',
    'status.line': '{n} 个工作区 · 端口 {p} · 显示器 {m}',
    'error.loadFail': '加载状态失败：',
    'error.selectRow': '请先选中一行',
    'error.idRange': 'ID 必须在 1-9 之间',
  },

  en: {
    'app.title': 'WorkspaceTool',

    'header.add': '＋ Add workspace',
    'header.import': 'Import',
    'header.export': 'Export',
    'header.rules': 'Rules',
    'header.settings': '⚙ Settings',
    'header.lang': '中',

    'footer.hint': 'Drag a window between cards to move · Hold <kbd>Ctrl</kbd> while dragging to copy · <kbd>Esc</kbd> closes panels',

    'drawer.settings.title': 'Settings',
    'settings.global': 'Global hotkeys',
    'settings.panelHotkey': 'Open manager panel',
    'settings.managerHotkey': 'Open manager (alt)',
    'settings.reloadHotkey': 'Reload config',
    'settings.undoHotkey': 'Undo last switch',
    'settings.prevWorkspaceHotkey': 'Previous workspace (default: mouse XButton1)',
    'settings.nextWorkspaceHotkey': 'Next workspace (default: mouse XButton2)',
    'settings.behavior': 'Behavior',
    'settings.switchToast': 'Switch toast (center popup on workspace switch)',
    'settings.trayBadge': 'Tray tooltip badge (show active workspace in tray)',
    'settings.focusMode': 'Focus mode (minimize windows not in current workspace)',
    'settings.captureThumbnails': 'Capture window thumbnails on snapshot (adds ~5KB per window)',
    'settings.previewSize': 'Hover preview size',
    'settings.stickyEnabled': 'Enable sticky windows',
    'settings.stickyTitle': 'Sticky windows list',
    'settings.stickyDesc': 'Windows matching these patterns are always visible in all workspaces and never captured into a workspace snapshot.',
    'settings.stickyPlaceholder': 'ahk_exe wechat.exe   or   ahk_class TXGuiFoundation',

    'drawer.rules.title': 'Rules',
    'rules.blacklist': 'Blacklist',
    'rules.blacklistDesc': 'Windows matching any pattern below are never captured into a workspace snapshot.',
    'rules.blacklistPlaceholder': 'ahk_exe somethingbad.exe',
    'rules.perApp': 'Per-app rules',
    'rules.perAppDesc': 'Override how specific apps are restored.',
    'rules.exe': 'Process (exe)',
    'rules.maxim': 'Always maximize',
    'rules.monitor': 'Prefer monitor',
    'rules.addRule': 'Add rule',

    'recorder.title': 'Record hotkey',
    'recorder.desc': 'Press the key combination (e.g. <kbd>Ctrl+Alt+W</kbd>). Mouse: <kbd>middle</kbd>, <kbd>XButton1/2</kbd>, or <kbd>modifier+wheel</kbd>.',
    'recorder.label': 'Record hotkey · {label}',
    'recorder.empty': '(none)',
    'button.add': 'Add',
    'button.pick': 'Pick…',
    'button.clear': 'Clear',
    'button.cancel': 'Cancel',
    'button.ok': 'OK',
    'button.import': 'Import',

    'picker.title': 'Add a live window',
    'picker.desc': 'Pick a currently-open window to add to this workspace.',

    'import.title': 'Import configuration',
    'import.desc': 'Paste a previously exported JSON payload. This will overwrite your settings/workspaces/rules.',
    'import.invalid': 'Invalid JSON: {err}',

    'ws.add': '＋ New workspace',
    'ws.empty': 'No windows captured.',
    'ws.addWindow': '＋ Add window',
    'ws.iconTitle': 'Click to change icon',
    'ws.snapshot': 'Snapshot current windows into this workspace',
    'ws.restore': 'Restore this workspace',
    'ws.delete': 'Delete this workspace',
    'ws.removeWin': 'Remove from workspace',
    'ws.chipRestore': 'Restore',
    'ws.chipSave': 'Save',
    'ws.chipTitle': 'Click to record hotkey',

    'prompt.wsName': 'Workspace name?',
    'prompt.wsNameDefault': 'Untitled',
    'prompt.snapshot': 'Capture currently-open windows as the initial snapshot?',
    'confirm.deleteWs': 'Delete workspace "{name}"?',
    'prompt.icon': 'Icon (emoji or character):',
    'prompt.saveIdPrompt': 'Save current windows to workspace ID (1-9):',

    'flash.exported': 'Exported to clipboard.',
    'status.line': '{n} workspace(s) · port {p} · monitors {m}',
    'error.loadFail': 'Failed to load state: ',
    'error.selectRow': 'Select a row first',
    'error.idRange': 'ID must be 1-9',
  },
};

let currentLang = localStorage.getItem('wt.lang') || 'zh';

function t(key, vars) {
  let s = (I18N[currentLang] && I18N[currentLang][key]) || I18N.en[key] || key;
  if (vars) {
    for (const k in vars) s = s.replace(new RegExp(`\\{${k}\\}`, 'g'), vars[k]);
  }
  return s;
}

function applyStaticI18n() {
  document.documentElement.lang = currentLang === 'zh' ? 'zh-CN' : 'en';
  document.title = t('app.title');
  document.querySelectorAll('[data-i18n]').forEach(el => {
    el.textContent = t(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-html]').forEach(el => {
    el.innerHTML = t(el.dataset.i18nHtml);
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    el.title = t(el.dataset.i18nTitle);
  });
}

function setLang(lang) {
  currentLang = lang;
  localStorage.setItem('wt.lang', lang);
  applyStaticI18n();
  if (state.workspaces) renderGrid();
  renderSettings();
  renderRules();
}

// ============================================================
// State + API
// ============================================================
const API = (path, opts = {}) => fetch(path, {
  headers: { 'Content-Type': 'application/json' },
  ...opts,
}).then(r => r.ok ? r.json() : r.text().then(t => { throw new Error(t || r.statusText); }));

let state = {
  workspaces: [],
  active: '',
  settings: {},
  rules: { blacklist: [], perApp: {} },
  monitorCount: 1,
};

async function refresh() {
  const s = await API('/api/state');
  state = {
    workspaces: s.workspaces || [],
    active: s.active || '',
    settings: s.settings || {},
    rules: s.rules || { blacklist: [], perApp: {} },
    monitorCount: s.monitorCount || 1,
  };
  document.getElementById('version-tag').textContent = 'v' + s.version;
  document.getElementById('status-line').textContent =
    t('status.line', { n: state.workspaces.length, p: s.port, m: state.monitorCount });
  renderGrid();
  renderSettings();
  renderRules();
}

// ============================================================
// Workspace grid render
// ============================================================
const grid = document.getElementById('workspace-grid');

function renderGrid() {
  grid.innerHTML = '';
  state.workspaces.forEach((ws, idx) => {
    grid.appendChild(renderWorkspaceCard(ws, idx));
  });
  const addCard = el('button', { class: 'ws-card-add', onclick: addWorkspace }, t('ws.add'));
  grid.appendChild(addCard);
}

function renderWorkspaceCard(ws, idx) {
  const card = el('article', {
    class: 'ws-card' + (state.active === ws.id ? ' active' : ''),
    'data-ws-id': ws.id,
    ondragenter: (e) => { if (dragInfo) { e.preventDefault(); } },
    ondragover: (e) => onCardDragOver(e, card),
    ondragleave: (e) => onCardDragLeave(e, card),
    ondrop: (e) => onCardDrop(e, ws, card),
  });

  const head = el('div', { class: 'ws-head' });

  const titleRow = el('div', { class: 'ws-title-row' });
  const icon = el('span', {
    class: 'ws-icon',
    title: t('ws.iconTitle'),
    onclick: () => editIcon(ws),
  }, ws.icon || '📋');
  const name = el('input', {
    class: 'ws-name',
    type: 'text',
    value: ws.name,
    spellcheck: 'false',
    onchange: (e) => updateWorkspace(ws.id, { name: e.target.value }),
  });
  const actions = el('div', { class: 'ws-actions' });
  actions.appendChild(el('button', {
    title: t('ws.snapshot'),
    onclick: () => snapshotWorkspace(ws.id),
  }, '📸'));
  actions.appendChild(el('button', {
    title: t('ws.restore'),
    onclick: () => restoreWorkspace(ws.id),
  }, '↻'));
  actions.appendChild(el('button', {
    class: 'btn-danger',
    title: t('ws.delete'),
    onclick: () => deleteWorkspace(ws.id),
  }, '✕'));

  titleRow.append(icon, name, actions);
  head.append(titleRow);

  const hkRow = el('div', { class: 'ws-hotkeys' });
  hkRow.appendChild(renderHotkeyChip(t('ws.chipRestore'), ws.hotkey, (val) => updateWorkspace(ws.id, { hotkey: val })));
  hkRow.appendChild(renderHotkeyChip(t('ws.chipSave'), ws.saveHotkey, (val) => updateWorkspace(ws.id, { saveHotkey: val })));
  head.append(hkRow);

  const body = el('div', { class: 'ws-body' });
  if (!ws.windows || ws.windows.length === 0) {
    body.appendChild(el('div', { class: 'ws-empty' }, t('ws.empty')));
  } else {
    ws.windows.forEach((win, i) => {
      body.appendChild(renderWindowRow(win, ws, i));
    });
  }
  body.appendChild(el('div', {
    class: 'ws-add-window',
    onclick: () => openWindowPicker(ws),
  }, t('ws.addWindow')));

  card.append(head, body);
  return card;
}

function renderHotkeyChip(label, value, onSet) {
  const chip = el('div', {
    class: 'hk-chip' + (value ? '' : ' empty'),
    title: t('ws.chipTitle'),
    onclick: () => openRecorder(label, value, onSet),
  });
  chip.appendChild(el('span', { class: 'hk-label' }, label));
  chip.appendChild(el('span', { class: 'hk-value' }, value || t('recorder.empty')));
  return chip;
}

function renderWindowRow(win, ws, idx) {
  const row = el('div', {
    class: 'win-row',
    draggable: 'true',
    'data-ws-id': ws.id,
    'data-win-idx': idx,
  });
  // Belt + suspenders — set draggable as both HTML attribute and JS property.
  row.setAttribute('draggable', 'true');
  row.draggable = true;
  row.addEventListener('dragstart', (e) => onWinDragStart(e, ws.id, idx, row));
  row.addEventListener('dragend', () => onWinDragEnd(row));
  let thumb;
  if (win.thumb) {
    thumb = el('img', {
      class: 'win-thumb',
      src: '/thumbs/' + win.thumb + '.jpg',
      alt: '',
      loading: 'lazy',
      draggable: 'false',
      onmouseenter: () => showThumbPreview(thumb),
      onmouseleave: () => hideThumbPreview(),
    });
  } else {
    thumb = el('div', { class: 'win-thumb win-thumb-fallback', draggable: 'false' }, (win.exe || '?').charAt(0).toUpperCase());
  }
  const text = el('div', { class: 'win-text' });
  text.appendChild(el('div', { class: 'win-title' }, win.title || '(untitled)'));
  text.appendChild(el('div', { class: 'win-meta' },
    `${win.exe || '?'} · M${win.monitor} · ${win.w}×${win.h}` +
    (win.folder ? ` · ${win.folder}` : '') +
    (win.url ? ` · ${shortUrl(win.url)}` : '') +
    (win.state === 1 ? ' · max' : '') +
    (win.state === -1 ? ' · min' : '')
  ));
  const rm = el('button', {
    class: 'win-remove',
    draggable: 'false',
    title: t('ws.removeWin'),
    onclick: (e) => { e.stopPropagation(); removeWindow(ws.id, idx); },
  }, '✕');
  row.append(thumb, text, rm);
  return row;
}

// ============================================================
// Drag-drop
// ============================================================
let dragInfo = null;
let dragging = false;

function dbg(msg) {
  const s = document.getElementById('status-line');
  if (s) {
    s.textContent = '[drag] ' + msg;
    s.style.color = 'var(--accent)';
  }
}

function onWinDragStart(e, fromWsId, fromIdx, row) {
  dragInfo = { fromWsId, fromIdx };
  dragging = true;
  row.classList.add('dragging');
  try {
    e.dataTransfer.effectAllowed = 'copyMove';
    e.dataTransfer.setData('text/plain', `${fromWsId}:${fromIdx}`);
  } catch (err) {}
  hideThumbPreview();
  dbg(`start ws=${fromWsId.slice(-6)} idx=${fromIdx}`);
}

function onWinDragEnd(row) {
  dragging = false;
  row.classList.remove('dragging');
  document.querySelectorAll('.ws-card').forEach(c => c.classList.remove('dragover', 'dragover-copy'));
}

function onCardDragOver(e, card) {
  if (!dragInfo) return;
  e.preventDefault();
  const copy = e.ctrlKey;
  e.dataTransfer.dropEffect = copy ? 'copy' : 'move';
  card.classList.toggle('dragover', !copy);
  card.classList.toggle('dragover-copy', copy);
}

function onCardDragLeave(e, card) {
  // Only clear when leaving the card entirely (not just a child).
  if (e.relatedTarget && card.contains(e.relatedTarget)) return;
  card.classList.remove('dragover', 'dragover-copy');
}

async function onCardDrop(e, dstWs, card) {
  e.preventDefault();
  card.classList.remove('dragover', 'dragover-copy');
  if (!dragInfo) {
    dbg('drop with no dragInfo');
    return;
  }
  const copy = e.ctrlKey;
  const info = dragInfo;
  dragInfo = null;
  dragging = false;
  dbg(`drop ${copy ? 'copy' : 'move'} -> ${dstWs.name}`);
  if (info.fromWsId === dstWs.id && !copy) return;
  try {
    await API(`/api/workspaces/${dstWs.id}/move-window`, {
      method: 'POST',
      body: JSON.stringify({
        from: info.fromWsId,
        fromIdx: info.fromIdx + 1,
        copy,
      }),
    });
    await refresh();
  } catch (err) {
    dbg('ERROR: ' + err.message);
  }
}

// ============================================================
// Workspace actions
// ============================================================
async function addWorkspace() {
  const name = prompt(t('prompt.wsName'), t('prompt.wsNameDefault')) || t('prompt.wsNameDefault');
  const snapshot = confirm(t('prompt.snapshot'));
  await API('/api/workspaces', {
    method: 'POST',
    body: JSON.stringify({ name, snapshot }),
  });
  await refresh();
}

async function updateWorkspace(id, patch) {
  await API(`/api/workspaces/${id}`, {
    method: 'PUT',
    body: JSON.stringify(patch),
  });
  await refresh();
}

async function deleteWorkspace(id) {
  const ws = state.workspaces.find(w => w.id === id);
  if (!confirm(t('confirm.deleteWs', { name: ws?.name }))) return;
  await API(`/api/workspaces/${id}`, { method: 'DELETE' });
  await refresh();
}

async function snapshotWorkspace(id) {
  await API(`/api/workspaces/${id}/snapshot`, { method: 'POST' });
  await refresh();
}

async function restoreWorkspace(id) {
  await API(`/api/workspaces/${id}/restore`, { method: 'POST' });
  await refresh();
}

async function removeWindow(wsId, idx) {
  await API(`/api/workspaces/${wsId}/windows/${idx + 1}`, { method: 'DELETE' });
  await refresh();
}

function editIcon(ws) {
  const next = prompt(t('prompt.icon'), ws.icon || '📋');
  if (next === null) return;
  updateWorkspace(ws.id, { icon: next || '📋' });
}

// ============================================================
// Window picker (add a live window)
// ============================================================
const pickerModal = document.getElementById('picker-modal');
const liveWindowsList = document.getElementById('live-windows');
document.getElementById('picker-cancel').addEventListener('click', () => pickerModal.classList.remove('open'));

async function openWindowPicker(ws) {
  const data = await API('/api/windows/live');
  liveWindowsList.innerHTML = '';
  data.windows.forEach(w => {
    const li = el('li', { onclick: () => addLiveWindow(ws.id, w.hwnd) });
    li.appendChild(el('span', { class: 'lw-title' }, w.title));
    li.appendChild(el('span', { class: 'lw-meta' }, `${w.exe} · ${w.class}`));
    liveWindowsList.appendChild(li);
  });
  pickerModal.classList.add('open');
}

async function addLiveWindow(wsId, hwnd) {
  pickerModal.classList.remove('open');
  await API(`/api/workspaces/${wsId}/capture-window`, {
    method: 'POST',
    body: JSON.stringify({ hwnd }),
  });
  await refresh();
}

// ============================================================
// Hotkey recorder
// ============================================================
const recorderModal = document.getElementById('recorder-modal');
const recorderDisplay = document.getElementById('recorder-display');
const recorderTitle = document.getElementById('recorder-title');
let recorderCallback = null;
let recorderValue = '';

document.getElementById('recorder-cancel').addEventListener('click', () => closeRecorder(false));
document.getElementById('recorder-ok').addEventListener('click', () => closeRecorder(true));
document.getElementById('recorder-clear').addEventListener('click', () => {
  recorderValue = '';
  recorderDisplay.textContent = t('recorder.empty');
});

function openRecorder(label, current, callback) {
  recorderTitle.textContent = t('recorder.label', { label });
  recorderValue = current || '';
  recorderDisplay.textContent = recorderValue || '…';
  recorderCallback = callback;
  recorderDisplay.setAttribute('tabindex', '0');
  recorderModal.classList.add('open');
  setTimeout(() => recorderDisplay.focus(), 40);
}

function closeRecorder(commit) {
  recorderModal.classList.remove('open');
  if (commit && recorderCallback) recorderCallback(recorderValue);
  recorderCallback = null;
}

function readKeyCombo(e) {
  const parts = [];
  if (e.ctrlKey) parts.push('Ctrl');
  if (e.altKey) parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
  if (e.metaKey) parts.push('Win');
  return parts;
}

function normalizeKey(key, code) {
  if (['Control', 'Alt', 'Shift', 'Meta', 'OS'].includes(key)) return null;
  if (key === ' ') return 'Space';
  if (key.length === 1) return key.toUpperCase();
  if (/^F\d+$/.test(key)) return key;
  const map = {
    ArrowLeft: 'Left', ArrowRight: 'Right', ArrowUp: 'Up', ArrowDown: 'Down',
    Enter: 'Enter', Tab: 'Tab', Escape: 'Esc',
    PageUp: 'PgUp', PageDown: 'PgDn',
    Backspace: 'Backspace', Delete: 'Delete', Insert: 'Insert',
    Home: 'Home', End: 'End',
  };
  if (map[key]) return map[key];
  if (code === 'Backquote') return '`';
  return key;
}

recorderDisplay.addEventListener('keydown', (e) => {
  e.preventDefault();
  e.stopPropagation();
  const parts = readKeyCombo(e);
  const k = normalizeKey(e.key, e.code);
  if (k) parts.push(k);
  if (parts.length === 0 || (parts.length === 1 && ['Ctrl','Alt','Shift','Win'].includes(parts[0]))) {
    recorderDisplay.textContent = parts.join('+') || '…';
    return;
  }
  recorderValue = parts.join('+');
  recorderDisplay.textContent = recorderValue;
});

recorderDisplay.addEventListener('mousedown', (e) => {
  if (e.button === 0 || e.button === 2) return;  // L/R reserved for normal UI
  e.preventDefault();
  const parts = readKeyCombo(e);
  if (e.button === 1) parts.push('MButton');
  else if (e.button === 3) parts.push('XButton1');
  else if (e.button === 4) parts.push('XButton2');
  else parts.push(`Mouse${e.button}`);
  recorderValue = parts.join('+');
  recorderDisplay.textContent = recorderValue;
});

recorderDisplay.addEventListener('wheel', (e) => {
  e.preventDefault();
  const parts = readKeyCombo(e);
  if (e.deltaY < 0) parts.push('WheelUp');
  else if (e.deltaY > 0) parts.push('WheelDown');
  else if (e.deltaX < 0) parts.push('WheelLeft');
  else if (e.deltaX > 0) parts.push('WheelRight');
  if (parts.length === 0) return;
  // Wheel without modifiers is dangerous (always-on scroll capture). Require a modifier.
  const hasMod = parts.some(p => ['Ctrl', 'Alt', 'Shift', 'Win'].includes(p));
  if (!hasMod) {
    recorderDisplay.textContent = 'Wheel needs a modifier (Ctrl/Alt/Shift/Win)';
    return;
  }
  recorderValue = parts.join('+');
  recorderDisplay.textContent = recorderValue;
}, { passive: false });

// ESC closes any open modal/drawer
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (recorderModal.classList.contains('open')) closeRecorder(false);
    else if (pickerModal.classList.contains('open')) pickerModal.classList.remove('open');
    else if (importModal.classList.contains('open')) importModal.classList.remove('open');
    else {
      document.querySelectorAll('.drawer.open').forEach(d => d.classList.remove('open'));
    }
  }
});

// ============================================================
// Settings drawer
// ============================================================
const settingsDrawer = document.getElementById('drawer-settings');
document.getElementById('btn-settings').addEventListener('click', () => settingsDrawer.classList.add('open'));
document.querySelectorAll('[data-close]').forEach(b => {
  b.addEventListener('click', () => document.getElementById(b.dataset.close).classList.remove('open'));
});

function renderSettings() {
  document.querySelectorAll('.hotkey-input[data-setting]').forEach(btn => {
    const key = btn.dataset.setting;
    const val = state.settings[key] || '';
    btn.textContent = val || t('recorder.empty');
    btn.classList.toggle('empty', !val);
    btn.onclick = () => {
      const lbl = btn.parentElement.querySelector('label')?.textContent || '';
      openRecorder(lbl, val, async (next) => {
        await updateSettings({ [key]: next });
      });
    };
  });
  document.querySelectorAll('input[data-setting-bool]').forEach(cb => {
    const key = cb.dataset.settingBool;
    cb.checked = !!state.settings[key];
    cb.onchange = () => updateSettings({ [key]: cb.checked ? 1 : 0 });
  });
  document.querySelectorAll('select[data-setting-select]').forEach(sel => {
    const key = sel.dataset.settingSelect;
    if (state.settings[key] != null)
      sel.value = state.settings[key];
    sel.onchange = () => updateSettings({ [key]: sel.value });
  });
  renderStickyList();
}

async function updateSettings(patch) {
  await API('/api/settings', { method: 'PUT', body: JSON.stringify(patch) });
  await refresh();
}

function renderStickyList() {
  const container = document.getElementById('sticky-list');
  container.innerHTML = '';
  const patterns = state.settings.stickyPatterns || [];
  patterns.forEach((pat, i) => {
    const row = el('div', { class: 'follow-row' });
    row.appendChild(el('code', {}, pat));
    row.appendChild(el('button', {
      title: t('ws.removeWin'),
      onclick: async () => {
        const next = [...patterns];
        next.splice(i, 1);
        await updateSettings({ stickyPatterns: next });
      }
    }, '✕'));
    container.appendChild(row);
  });
}

document.getElementById('btn-sticky-add').addEventListener('click', async () => {
  const input = document.getElementById('sticky-pattern');
  const val = input.value.trim();
  if (!val) return;
  const patterns = [...(state.settings.stickyPatterns || []), val];
  await updateSettings({ stickyPatterns: patterns });
  input.value = '';
});

document.getElementById('btn-sticky-pick').addEventListener('click', async () => {
  const data = await API('/api/windows/live');
  const list = document.getElementById('live-windows');
  list.innerHTML = '';
  data.windows.forEach(w => {
    const li = el('li', {
      onclick: async () => {
        pickerModal.classList.remove('open');
        const pat = 'ahk_exe ' + w.exe;
        const patterns = [...(state.settings.stickyPatterns || []), pat];
        await updateSettings({ stickyPatterns: patterns });
      }
    });
    li.appendChild(el('span', { class: 'lw-title' }, w.title));
    li.appendChild(el('span', { class: 'lw-meta' }, `${w.exe} · ${w.class}`));
    list.appendChild(li);
  });
  pickerModal.classList.add('open');
});

// ============================================================
// Rules drawer
// ============================================================
const rulesDrawer = document.getElementById('drawer-rules');
document.getElementById('btn-rules').addEventListener('click', () => rulesDrawer.classList.add('open'));

function renderRules() {
  const bl = document.getElementById('blacklist');
  bl.innerHTML = '';
  (state.rules.blacklist || []).forEach((pat, i) => {
    const row = el('div', { class: 'follow-row' });
    row.appendChild(el('code', {}, pat));
    row.appendChild(el('button', {
      title: t('ws.removeWin'),
      onclick: async () => {
        const next = [...(state.rules.blacklist || [])];
        next.splice(i, 1);
        await updateRules({ blacklist: next });
      }
    }, '✕'));
    bl.appendChild(row);
  });

  const tb = document.getElementById('perapp-body');
  tb.innerHTML = '';
  const perApp = state.rules.perApp || {};
  Object.keys(perApp).forEach(exe => {
    const r = perApp[exe];
    const tr = el('tr');
    tr.appendChild(el('td', {}, exe));

    const tdMax = el('td');
    const cb = el('input', {
      type: 'checkbox',
      onchange: async () => {
        const next = { ...perApp, [exe]: { ...r, alwaysMaximize: cb.checked ? 1 : 0 } };
        await updateRules({ perApp: next });
      }
    });
    cb.checked = !!r.alwaysMaximize;
    tdMax.appendChild(cb);
    tr.appendChild(tdMax);

    const tdMon = el('td');
    const num = el('input', {
      type: 'number',
      min: '0',
      max: String(state.monitorCount),
      value: r.preferMonitor || 0,
      onchange: async () => {
        const next = { ...perApp, [exe]: { ...r, preferMonitor: Number(num.value) || 0 } };
        await updateRules({ perApp: next });
      }
    });
    tdMon.appendChild(num);
    tr.appendChild(tdMon);

    const tdRm = el('td');
    tdRm.appendChild(el('button', {
      class: 'btn-danger',
      title: t('ws.removeWin'),
      onclick: async () => {
        const next = { ...perApp };
        delete next[exe];
        await updateRules({ perApp: next });
      }
    }, '✕'));
    tr.appendChild(tdRm);
    tb.appendChild(tr);
  });
}

async function updateRules(patch) {
  await API('/api/rules', { method: 'PUT', body: JSON.stringify(patch) });
  await refresh();
}

document.getElementById('btn-blacklist-add').addEventListener('click', async () => {
  const input = document.getElementById('blacklist-pattern');
  const val = input.value.trim();
  if (!val) return;
  const next = [...(state.rules.blacklist || []), val];
  await updateRules({ blacklist: next });
  input.value = '';
});

document.getElementById('btn-perapp-add').addEventListener('click', async () => {
  const input = document.getElementById('perapp-exe');
  const exe = input.value.trim();
  if (!exe) return;
  const next = { ...(state.rules.perApp || {}), [exe]: { alwaysMaximize: 0, preferMonitor: 0 } };
  await updateRules({ perApp: next });
  input.value = '';
});

// ============================================================
// Import / Export
// ============================================================
const importModal = document.getElementById('import-modal');

document.getElementById('btn-export').addEventListener('click', async () => {
  const data = await API('/api/export');
  const text = JSON.stringify(data, null, 2);
  try {
    await navigator.clipboard.writeText(text);
    flash(t('flash.exported'));
  } catch {
    const blob = new Blob([text], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = el('a', { href: url, download: `workspace-tool-${Date.now()}.json` });
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }
});

document.getElementById('btn-import').addEventListener('click', () => {
  document.getElementById('import-text').value = '';
  importModal.classList.add('open');
});
document.getElementById('import-cancel').addEventListener('click', () => importModal.classList.remove('open'));
document.getElementById('import-ok').addEventListener('click', async () => {
  const text = document.getElementById('import-text').value.trim();
  if (!text) return;
  try {
    JSON.parse(text);
  } catch (e) {
    alert(t('import.invalid', { err: e.message }));
    return;
  }
  await API('/api/import', { method: 'POST', body: text });
  importModal.classList.remove('open');
  await refresh();
});

// ============================================================
// Header buttons + language toggle
// ============================================================
document.getElementById('btn-add').addEventListener('click', addWorkspace);
document.getElementById('btn-lang').addEventListener('click', () => {
  setLang(currentLang === 'zh' ? 'en' : 'zh');
});

// ============================================================
// Small utilities
// ============================================================
function el(tag, attrs = {}, text) {
  const e = document.createElement(tag);
  for (const k in attrs) {
    if (k === 'class') e.className = attrs[k];
    else if (k.startsWith('on') && typeof attrs[k] === 'function') {
      e.addEventListener(k.slice(2).toLowerCase(), attrs[k]);
    }
    else if (k.startsWith('data-') || k === 'role' || k === 'title' || k === 'href' || k === 'download' || k === 'spellcheck' || k === 'tabindex' || k === 'min' || k === 'max' || k === 'placeholder' || k === 'alt' || k === 'loading' || k === 'draggable') {
      e.setAttribute(k, attrs[k]);
    }
    else e[k] = attrs[k];
  }
  if (text != null) e.textContent = text;
  return e;
}

function flash(msg) {
  const s = document.getElementById('status-line');
  const old = s.textContent;
  s.textContent = msg;
  s.style.color = 'var(--ok)';
  setTimeout(() => { s.textContent = old; s.style.color = ''; }, 1800);
}

function shortUrl(url) {
  try {
    const u = new URL(url);
    return u.hostname + u.pathname.replace(/\/$/, '') || u.href;
  } catch {
    return url.length > 50 ? url.slice(0, 50) + '…' : url;
  }
}

// ============================================================
// Thumbnail preview overlay (escapes overflow:hidden of ws-card)
// ============================================================
const previewOverlay = document.createElement('img');
previewOverlay.className = 'thumb-preview-overlay';
previewOverlay.alt = '';
previewOverlay.draggable = false;
previewOverlay.style.display = 'none';
document.body.appendChild(previewOverlay);

const PREVIEW_SIZES = {
  xs:  [240, 150],
  sm:  [400, 250],
  md:  [560, 350],
  lg:  [800, 500],
  xl:  [1100, 690],
  xxl: [1280, 800],
};

function getPreviewSize() {
  const key = (state.settings && state.settings.previewSize) || 'md';
  return PREVIEW_SIZES[key] || PREVIEW_SIZES.md;
}

function showThumbPreview(srcImg) {
  const rect = srcImg.getBoundingClientRect();
  previewOverlay.src = srcImg.src;

  const [baseW, baseH] = getPreviewSize();
  const margin = 8;
  const vpW = window.innerWidth;
  const vpH = window.innerHeight;
  const aspect = baseW / baseH;

  // Cap size to viewport (with margin) while preserving aspect ratio.
  let W = Math.min(baseW, vpW - margin * 2);
  let H = Math.min(baseH, vpH - margin * 2);
  if (W / H > aspect) W = Math.round(H * aspect);
  else H = Math.round(W / aspect);

  previewOverlay.style.width = W + 'px';
  previewOverlay.style.height = H + 'px';

  // Horizontal: try right of thumb, then left, then clamp to viewport.
  let x;
  if (rect.right + margin + W <= vpW) {
    x = rect.right + margin;
  } else if (rect.left - margin - W >= 0) {
    x = rect.left - margin - W;
  } else {
    x = Math.max(margin, vpW - W - margin);
  }

  // Vertical: center on thumb, then clamp.
  let y = rect.top + rect.height / 2 - H / 2;
  y = Math.max(margin, Math.min(y, vpH - H - margin));

  previewOverlay.style.left = x + 'px';
  previewOverlay.style.top = y + 'px';
  previewOverlay.style.display = 'block';
}

function hideThumbPreview() {
  previewOverlay.style.display = 'none';
}

// ============================================================
// Boot
// ============================================================
applyStaticI18n();
refresh().catch(err => {
  document.body.innerHTML = `<div style="padding:40px;color:#ff5e5e;font-family:monospace">${t('error.loadFail')}${err.message}</div>`;
});

// Track IME composition so we don't tear down the focused input mid-type.
let imeActive = false;
document.addEventListener('compositionstart', () => { imeActive = true; }, true);
document.addEventListener('compositionend', () => { imeActive = false; }, true);

setInterval(() => {
  if (document.visibilityState !== 'visible') return;
  if (imeActive) return;
  if (dragging) return;
  const a = document.activeElement;
  if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable)) return;
  refresh().catch(() => {});
}, 4000);
