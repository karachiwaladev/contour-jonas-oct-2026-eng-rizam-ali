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

let db;

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
const addTask = (title) => run('readwrite', (s) => s.add({ title, done: false, createdAt: Date.now() }));
const putTask = (task) => run('readwrite', (s) => s.put(task));
const deleteTask = (id) => run('readwrite', (s) => s.delete(id));

function showError(message) {
  errorMsg.textContent = message;
  errorMsg.hidden = !message;
}

function renderTask(task) {
  const li = document.createElement('li');
  li.className = 'task' + (task.done ? ' done' : '');
  li.dataset.id = task.id;

  const check = document.createElement('input');
  check.type = 'checkbox';
  check.checked = task.done;
  check.setAttribute('aria-label', `Mark "${task.title}" done`);

  const title = document.createElement('span');
  title.className = 'title';
  title.textContent = task.title; // textContent, never innerHTML: user text stays text

  const del = document.createElement('button');
  del.type = 'button';
  del.className = 'delete';
  del.textContent = 'Delete';
  del.setAttribute('aria-label', `Delete "${task.title}"`);

  li.append(check, title, del);
  return li;
}

async function render() {
  const tasks = (await getAll()).sort((a, b) => a.createdAt - b.createdAt);
  list.replaceChildren(...tasks.map(renderTask));

  const open = tasks.filter((t) => !t.done).length;
  emptyMsg.hidden = tasks.length > 0;
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
  guarded(async () => {
    await addTask(title);
    input.value = '';
    input.focus();
  });
});

list.addEventListener('change', (event) => {
  if (!event.target.matches('input[type="checkbox"]')) return;
  const id = Number(event.target.closest('.task').dataset.id);
  guarded(async () => {
    const tasks = await getAll();
    const task = tasks.find((t) => t.id === id);
    if (task) await putTask({ ...task, done: event.target.checked });
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
