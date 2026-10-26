# Todo

A small todo app that runs entirely in the browser. Built for Ticket #3 (issue #4) and extended for
Ticket #4 (issue #5).

## What it does
- Add a task, mark it done (and undo that), delete it
- **Due date** (optional): overdue open tasks show in red, tasks due today are highlighted
- **Tags** (optional): type them comma-separated when adding, e.g. `home, bills`
- **Filters:** show All, Incomplete or Completed tasks, and narrow by one tag. The two filters combine.

Tasks are stored in the browser's own database (IndexedDB), so they survive a reload.
There is no server, build step or dependency, and the data never leaves the device.

## Run it
Serve the folder with any static file server and open it in a browser. For example:

```
python -m http.server 8000 --directory todo
```

then visit http://localhost:8000.

Opening `index.html` straight from disk (`file://`) was not verified, and some browsers restrict IndexedDB there.

## How it behaves
- **Tags** are lowercased, trimmed and de-duplicated. Each is cut to 24 characters, and a task keeps at most 10.
- **Tag filter:** the row lists the tags currently in use. Click a tag to filter, click it again (or "All tags") to clear. If the last task with the selected tag is deleted, the filter resets.
- **Counts:** "N of M left" always counts every task, whichever filter is on.
- **Filters are not saved:** they reset to All / All tags on reload. Tasks, dates and tags are saved.
- **Older tasks** saved before due dates and tags existed still work: they simply have no date and no tags.
- A done task is never shown as overdue.
- Not included: editing a task after it is created, sorting by due date, and reminders.

## Data
Each task in IndexedDB (`todo-app`, store `tasks`):

| Field | Type | Notes |
|---|---|---|
| `id` | number | auto-generated |
| `title` | string | up to 200 characters |
| `done` | boolean | |
| `createdAt` | number | milliseconds, used for list order |
| `due` | string or null | `YYYY-MM-DD`, in the user's local time |
| `tags` | string[] | already cleaned as described above |

## Files
| File | Purpose |
|---|---|
| `index.html` | Page structure |
| `style.css` | Styling, with automatic light and dark themes |
| `app.js` | IndexedDB storage, add, toggle and delete, filters, due dates and tags |
| `docs/screenshots/` | Screenshots from the browser verification (ticket #5) |

## Verified
Driven in headless Edge over the DevTools Protocol against `http://localhost`, with 30 checks passing and no
console errors: older tasks still render, tag cleaning (case, duplicates, length, count, HTML as plain text),
overdue / today / future labels, each status filter, tag filter alone and combined with status, filter reset when a
tag disappears, the "no match" message, persistence across reload, and no horizontal scroll at 390 px.
Task text and tags are inserted with `textContent`, so they are never interpreted as HTML.
