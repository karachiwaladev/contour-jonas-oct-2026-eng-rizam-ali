// Todo app. Tasks live in IndexedDB, a database built into the browser,
// so they survive reloads and nothing is sent to a server.

const DB_NAME = 'todo-app';
const STORE = 'tasks';

const form = document.getElementById('add-form');
const input = document.getElementById('new-task');
const list = document.getElementById('task-list');
const emptyMsg = document.getElementById('empty');
const summary = document.getElementById('summary');
const errorMsg = document.getElementById('error');
const dueInput = document.getElementById('new-due');
const tagsInput = document.getElementById('new-tags');
const repeatInput = document.getElementById('new-repeat');
const filters = document.getElementById('filters');
const statusFilter = document.getElementById('status-filter');
const tagFilter = document.getElementById('tag-filter');
const noMatch = document.getElementById('no-match');

const MAX_TAG_LENGTH = 24;
const MAX_TAGS = 10;

let db;
// Filters live in memory only and reset on reload.
let selectedStatus = 'all'; // 'all' | 'incomplete' | 'completed'
let selectedTag = null;     // one tag, or null for all tags

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      req.result.createObjectStore(STORE, { keyPath: 'id', autoIncrement: true });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

// Runs one operation on the store and resolves once the transaction commits.
function run(mode, op) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const request = op(tx.objectStore(STORE));
    tx.oncomplete = () => resolve(request && request.result);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

const getAll = () => run('readonly', (s) => s.getAll());
// Tasks saved before due dates and tags existed have neither field: treat them as no date, no tags.
// `repeat` is null or one of REPEATS and only makes sense with a due date. Older tasks have no `repeat`.
const newTask = (title, due, tags, repeat) =>
  ({ title, done: false, createdAt: Date.now(), due, tags, repeat });
const addTask = (title, due, tags, repeat) => run('readwrite', (s) => s.add(newTask(title, due, tags, repeat)));
const putTask = (task) => run('readwrite', (s) => s.put(task));
// Marks a recurring task done and adds its next occurrence in one transaction, so both happen or neither does.
const completeAndSpawn = (task, next) =>
  run('readwrite', (s) => {
    s.put({ ...task, done: true, spawned: true });
    return s.add(newTask(task.title, next, task.tags || [], task.repeat));
  });
const deleteTask = (id) => run('readwrite', (s) => s.delete(id));

function showError(message) {
  errorMsg.textContent = message;
  errorMsg.hidden = !message;
}

// "a, B ,a,,  work   stuff" -> ['a', 'b', 'work stuff']
function parseTags(text) {
  const tags = [];
  for (const raw of text.split(',')) {
    const tag = raw.trim().toLowerCase().replace(/\s+/g, ' ').slice(0, MAX_TAG_LENGTH).trim();
    if (tag && !tags.includes(tag)) tags.push(tag);
    if (tags.length === MAX_TAGS) break;
  }
  return tags;
}

// Today as 'YYYY-MM-DD' in the user's own time zone, comparable with the date input's value.
function todayString() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const REPEATS = ['daily', 'weekly', 'monthly', 'yearly'];

function toDateString(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

// One step of a repeat from 'YYYY-MM-DD', in local calendar dates. Monthly and yearly clamp to the
// end of a shorter month (31 Jan -> 28 Feb, 29 Feb -> 28 Feb).
function stepDate(iso, repeat) {
  const [y, m, d] = iso.split('-').map(Number);
  if (repeat === 'daily') return toDateString(new Date(y, m - 1, d + 1));
  if (repeat === 'weekly') return toDateString(new Date(y, m - 1, d + 7));
  const months = repeat === 'monthly' ? 1 : 12;
  const lastDay = new Date(y, m - 1 + months + 1, 0).getDate(); // last day of the target month
  return toDateString(new Date(y, m - 1 + months, Math.min(d, lastDay)));
}

// Next due date: one step after `due`. A task finished late skips ahead to the first date after today,
// so completing it never leaves a pile of overdue copies.
function nextDue(due, repeat) {
  const today = todayString();
  let next = stepDate(due, repeat);
  while (next <= today) next = stepDate(next, repeat);
  return next;
}

function formatDate(iso, withWeekday) {
  const [y, m, d] = iso.split('-').map(Number);
  const options = withWeekday ? { weekday: 'short', day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short' };
  return new Date(y, m - 1, d).toLocaleDateString(undefined, options);
}

function dueLabel(task) {
  if (!task.due) return null;
  const el = document.createElement('span');
  el.className = 'due';
  const today = todayString();
  if (!task.done && task.due < today) {
    el.classList.add('overdue');
    el.textContent = `Overdue · ${formatDate(task.due, false)}`;
  } else if (!task.done && task.due === today) {
    el.classList.add('today');
    el.textContent = 'Due today';
  } else {
    el.textContent = `Due ${formatDate(task.due, true)}`;
  }
  return el;
}

function renderTask(task) {
  const li = document.createElement('li');
  li.className = 'task' + (task.done ? ' done' : '');
  li.dataset.id = task.id;

  const check = document.createElement('input');
  check.type = 'checkbox';
  check.checked = task.done;
  check.setAttribute('aria-label', `Mark "${task.title}" done`);

  const body = document.createElement('div');
  body.className = 'body';

  const title = document.createElement('span');
  title.className = 'title';
  title.textContent = task.title; // textContent, never innerHTML: user text stays text
  body.append(title);

  const due = dueLabel(task);
  const tags = task.tags || [];
  const repeats = REPEATS.includes(task.repeat) && task.due;
  if (due || repeats || tags.length) {
    const meta = document.createElement('div');
    meta.className = 'meta';
    if (due) meta.append(due);
    if (repeats) {
      const rep = document.createElement('span');
      rep.className = 'repeat';
      rep.textContent = `Repeats ${task.repeat}`;
      meta.append(rep);
    }
    for (const tag of tags) {
      const chip = document.createElement('span');
      chip.className = 'tag';
      chip.textContent = tag;
      meta.append(chip);
    }
    body.append(meta);
  }

  const del = document.createElement('button');
  del.type = 'button';
  del.className = 'delete';
  del.textContent = 'Delete';
  del.setAttribute('aria-label', `Delete "${task.title}"`);

  li.append(check, body, del);
  return li;
}

function renderFilters(tags) {
  for (const btn of statusFilter.querySelectorAll('button')) {
    btn.setAttribute('aria-pressed', String(btn.dataset.status === selectedStatus));
  }
  tagFilter.hidden = tags.length === 0;
  const chips = [null, ...tags].map((tag) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chip';
    btn.dataset.tag = tag === null ? '' : tag;
    btn.textContent = tag === null ? 'All tags' : tag;
    btn.setAttribute('aria-pressed', String(tag === selectedTag));
    return btn;
  });
  tagFilter.replaceChildren(...chips);
}

async function render() {
  const tasks = (await getAll()).sort((a, b) => a.createdAt - b.createdAt);

  const tags = [...new Set(tasks.flatMap((t) => t.tags || []))].sort();
  if (selectedTag !== null && !tags.includes(selectedTag)) selectedTag = null;

  const visible = tasks.filter((t) => {
    if (selectedStatus === 'incomplete' && t.done) return false;
    if (selectedStatus === 'completed' && !t.done) return false;
    if (selectedTag !== null && !(t.tags || []).includes(selectedTag)) return false;
    return true;
  });
  list.replaceChildren(...visible.map(renderTask));

  const open = tasks.filter((t) => !t.done).length;
  filters.hidden = tasks.length === 0;
  renderFilters(tags);
  emptyMsg.hidden = tasks.length > 0;
  noMatch.hidden = tasks.length === 0 || visible.length > 0;
  summary.hidden = tasks.length === 0;
  summary.textContent = `${open} of ${tasks.length} left`;
}

async function guarded(action) {
  try {
    showError('');
    await action();
    await render();
  } catch (err) {
    showError('Could not save your change: ' + (err && err.message ? err.message : err));
  }
}

form.addEventListener('submit', (event) => {
  event.preventDefault();
  const title = input.value.trim();
  if (!title) return;
  const due = /^\d{4}-\d{2}-\d{2}$/.test(dueInput.value) ? dueInput.value : null;
  const tags = parseTags(tagsInput.value);
  const repeat = due && REPEATS.includes(repeatInput.value) ? repeatInput.value : null;
  guarded(async () => {
    await addTask(title, due, tags, repeat);
    input.value = '';
    dueInput.value = '';
    tagsInput.value = '';
    syncRepeat();
    input.focus();
  });
});

// Repeating needs a due date to count from: the select is only usable while one is set.
function syncRepeat() {
  const hasDue = /^\d{4}-\d{2}-\d{2}$/.test(dueInput.value);
  repeatInput.disabled = !hasDue;
  if (!hasDue) repeatInput.value = '';
}
dueInput.addEventListener('input', syncRepeat);

statusFilter.addEventListener('click', (event) => {
  const btn = event.target.closest('button[data-status]');
  if (!btn) return;
  selectedStatus = btn.dataset.status;
  guarded(async () => {});
});

tagFilter.addEventListener('click', (event) => {
  const btn = event.target.closest('button[data-tag]');
  if (!btn) return;
  const tag = btn.dataset.tag || null;
  selectedTag = tag === selectedTag ? null : tag; // clicking the active chip clears it
  guarded(async () => {});
});

list.addEventListener('change', (event) => {
  if (!event.target.matches('input[type="checkbox"]')) return;
  const id = Number(event.target.closest('.task').dataset.id);
  guarded(async () => {
    const tasks = await getAll();
    const task = tasks.find((t) => t.id === id);
    if (!task) return;
    const done = event.target.checked;
    // Only the first completion adds the next occurrence: undoing and redoing it must not add another.
    if (done && !task.done && !task.spawned && task.due && REPEATS.includes(task.repeat)) {
      await completeAndSpawn(task, nextDue(task.due, task.repeat));
    } else {
      await putTask({ ...task, done });
    }
  });
});

list.addEventListener('click', (event) => {
  if (!event.target.matches('.delete')) return;
  const id = Number(event.target.closest('.task').dataset.id);
  guarded(() => deleteTask(id));
});

(async function init() {
  if (!('indexedDB' in window)) {
    showError('This browser does not support IndexedDB, so tasks cannot be saved.');
    form.querySelectorAll('input, button').forEach((el) => { el.disabled = true; });
    return;
  }
  try {
    db = await openDb();
    await render();
  } catch (err) {
    showError('Could not open the task database: ' + (err && err.message ? err.message : err));
  }
})();
