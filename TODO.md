# TODO — RescueTime Personal Overview

Shared task list. Reference any item by its **number**, e.g. "do #1" or
"let's discuss #4". Numbers are **stable** — they are never reused or
renumbered. When an item is finished or a decision is made, move it to
**Done** (keep its number + a one-line note).

**Next free IDs** (cut the first one when you add a task):
`8  9  10  11  12  13  14  15  16  17`

### Template — copy a line, then double-click **ID** / **Task** / **Description** to overwrite each

```
- [ ] **#ID — Task.** Description
```

## Open tasks

- [ ] **#1 — Highlights page.** Build the real Highlights page. The History /
  document icon on the pulse card currently opens a blank page; it should show
  your RescueTime highlights (and, ideally, let you add one).

- [ ] **#2 — Click-through to category details.** Clicking a category bar *or*
  the category text on an app's detail page should open that category's detail
  page. The combined-name bars at the bottom of a detail page should also link
  through to the right category / app.

- [ ] **#5 — Full quality-assurance & refactor pass.** Do a complete QA review
  of the whole codebase — `All-Data.html`, `styles.css`, `index.html`, the
  fetch script (`fetch-addition.py` / `Fetch-Data.ps1`) and the other PS1
  scripts. Hunt for bugs, dead code, duplication and anything fragile, then
  refactor and optimise where it's safe (clearer/smaller functions, readability,
  performance) **without changing behaviour or the data format**. Verify against
  the real staged data and flag anything risky before touching it.

- [ ] **#6 — Scroll / drag the charts through time.** On the vertical bar charts
  and line graphs, let the mouse wheel or a click-and-drag pan the x-axis
  backwards and forwards one step at a time — a day when the axis is in days, a
  week when it's weeks, a month when it's months, etc. — so you can look at
  earlier or later periods without leaving the chart. Allow panning back a large
  but performance-reasonable range. A quick click on a bar must keep its current
  behaviour (close the detail page); only a deliberate drag or wheel scroll
  should pan. (Related to the existing Trends Prior/Next buttons — this would be
  the same idea via wheel/drag, ideally on every chart.)

- [ ] **#7 — Show a manual activity's details on its detail page.** When you log
  a manual/offline activity on the Manual Activities page you can add a note in
  the "Add details about your time" field (e.g. an entry named "Meetings
  (offline)" with a note about what the meeting was). That note is saved with the
  entry but isn't shown anywhere afterwards. On that activity's own detail page,
  each recorded row/entry should display the details note that was saved with it,
  so you can see per-occurrence what each logged block was about.

## Ideas / decisions

- [ ] **#4 — Rename "Apps" → "Activities" across the UI?** RescueTime itself
  calls them "activities" (games, sites, offline entries — not all are apps).
  Claude's take: changing the *visible* text (headlines, buttons, labels) and
  the dictionary section key is low-risk (add a backward-compatible alias so
  old dictionaries keep working); renaming the *internal* code identifiers
  (`appName`, `#appSearch`, the `app:` search key, etc.) is pure refactoring
  risk with no user benefit and is best left alone. Decide whether to proceed.

## Done

- [x] **#3 — Edit names & types from the detail page.** 2026-07-24 — WON'T DO.
  The dashboard is a static site (local server + GitHub Pages), so the browser
  cannot write `dictionary.json`. An in-page editor could only ever copy/paste
  a snippet, which isn't worth the clutter. Dictionary edits stay manual in
  VS Code.

<!-- move finished/decided items here, keeping their number, e.g.:
- [x] #0 — 2026-07-24 — example done item (v111)
-->

<!-- next free id: 8 -->
