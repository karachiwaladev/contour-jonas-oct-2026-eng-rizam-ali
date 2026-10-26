# Todo

A small todo app that runs entirely in the browser. Built for Ticket #3 (issue #4) and extended for
Ticket #4 (issue #5).

## What it does
- Add a task, mark it done (and undo that), delete it
- **Due date** (optional): overdue open tasks show in red, tasks due today are highlighted
- **Tags** (optional): type them comma-separated when adding, e.g. `home, bills`
- **Filters:** show All, Incomplete or Completed tasks, and narrow by one tag. The two filters combine.
- **Recurring tasks** (optional, needs a due date): repeat daily, weekly, monthly or yearly. Marking one done adds
  the next occurrence with the next due date.

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
- **Repeats** count from the original due date, so a weekly Monday task stays on Mondays. Finishing one late skips
  ahead to the first matching date after today instead of leaving overdue copies. Monthly and yearly clamp to the
  end of a short month (31 Jan -> 28 Feb, 29 Feb -> 28 Feb).
- Only the first completion adds the next occurrence: unticking and re-ticking never adds another.
- The Repeat choice is only usable once a due date is set. To stop a series, delete the open occurrence.
- Not included: editing a task after it is created, custom intervals, end dates, sorting by due date, and reminders.

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
| `docs/screenshots/` | Screenshots from the browser verification (tickets #5 and #6) |

## Verified
Driven in headless Edge over the DevTools Protocol against `http://localhost`, with 30 checks passing and no
console errors: older tasks still render, tag cleaning (case, duplicates, length, count, HTML as plain text),
overdue / today / future labels, each status filter, tag filter alone and combined with status, filter reset when a
tag disappears, the "no match" message, persistence across reload, and no horizontal scroll at 390 px.
Task text and tags are inserted with `textContent`, so they are never interpreted as HTML.

Recurring tasks (ticket #6) were checked in Chrome through chrome-devtools against `http://localhost`: each repeat step
including month-end and leap-year clamping, a late completion skipping ahead and staying on its weekday, the next
occurrence being created on completion, undo and redo adding no duplicate, a non-recurring task adding nothing, the
Repeat select disabled without a due date, an older task without a `repeat` field, and persistence across a reload.
Checked at a 502 px window (the smallest this browser allowed) with no horizontal scroll. Not tested: real elapsed
time (dates were seeded), or other browsers.
