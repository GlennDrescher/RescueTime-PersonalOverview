# TODO — RescueTime Personal Overview

Shared task list for this project. Edit it freely in VS Code — Claude also reads
and updates it. Mark items `- [ ]` (open) or `- [x]` (done); move finished
items to the **Done** section with a short note.

## Open

- [ ] **Highlights page** — build the real Highlights page. The History /
  document icon on the pulse card currently opens a blank page; it should show
  your RescueTime highlights (and, ideally, let you add one).

- [ ] **Click-through to category details** — clicking a category bar *or* the
  category text on an app's detail page should open that category's detail
  page. The combined-name bars at the bottom of a detail page should also link
  through to the right category / app.

- [ ] **Edit names & types from the detail page** — change category names,
  category types, and app names directly inside the relevant detail page (which
  writes the change into `dictionary.json`), instead of hand-editing the JSON.

## Ideas / decisions

- [ ] **Rename "Apps" → "Activities" across the UI?** RescueTime itself calls
  them "activities" (games, sites, offline entries — not all are apps). Claude's
  take: changing the *visible* text (headlines, buttons, labels) and the
  dictionary section key is low-risk (add a backward-compatible alias so old
  dictionaries keep working); renaming the *internal* code identifiers
  (`appName`, `#appSearch`, the `app:` search key, etc.) is pure refactoring
  risk with no user benefit and is best left alone. Decide whether to proceed
  with the text + dictionary-key rename.

## Done

<!-- move finished items here with a one-line note, e.g.
- [x] 2026-07-24 — App detail shows category + type row (v110)
-->
