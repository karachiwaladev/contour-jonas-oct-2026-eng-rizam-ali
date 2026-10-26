# Todo

A small todo app that runs entirely in the browser. Built for Ticket #3 (issue #4).

## What it does
- Add a task
- Mark a task done (and undo it)
- Delete a task

Tasks are stored in the browser's own database (IndexedDB), so they survive a reload.
There is no server, build step or dependency, and the data never leaves the device.

## Run it
Serve the folder with any static file server and open it in a browser. For example:

```
python -m http.server 8000 --directory todo
```

then visit http://localhost:8000.

Tested over `http://localhost` in Edge (add, mark done, undo, delete, empty input, reload-safe storage).
Opening `index.html` straight from disk (`file://`) was not verified, and some browsers restrict IndexedDB there.

## Files
| File | Purpose |
|---|---|
| `index.html` | Page structure |
| `style.css` | Styling, with automatic light and dark themes |
| `app.js` | IndexedDB storage and the add, toggle and delete behaviour |

## Notes
- Data is per browser and per origin. A different browser, or `file://` versus `localhost`, has its own list.
- Task text is inserted with `textContent`, so it is never interpreted as HTML.
