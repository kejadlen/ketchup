# Multi-View Dashboard Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let the user switch between four dashboard views — list, focus, calendar, and agenda — each suited to a different mindset. Enrich the existing list view with series scorecard data.

**Architecture:** Four server-rendered routes share a common layout with a client-side panel. Clicking a task in any view fetches the series detail as an HTML fragment and slides it open without a page reload. Each view is a small Phlex class; the panel is Alpine-managed.

**Tech Stack:** Ruby, Roda, Phlex, Alpine.js, OverType (existing stack — no new dependencies)

---

## Routes

```
GET /                     List view (current dashboard, enriched)
GET /focus                Focus view
GET /calendar             Calendar view
GET /agenda               Agenda view
GET /series/:id/panel     Panel HTML fragment (new endpoint)
```

No per-view series routes. Clicking a task in any view fetches `/series/:id/panel` via JavaScript, injects the response into the panel div, and Alpine opens the panel. The URL does not change — the panel is ephemeral UI state.

Completing a task POSTs to `/series/:id/tasks/:id/complete` as today. The redirect returns the user to whichever view they came from, determined by a hidden field or `Referer` header, not to `/series/:id`.

Creating a series, editing user settings, and all PATCH endpoints remain unchanged.

## View architecture

A shared layout — the existing `Layout` class — renders the header with the view switcher, an empty panel shell, and the footer. Each view fills the main content area:

- `Views::TaskList` — the current dashboard main column (overdue + upcoming), enriched with inline streak indicators on each task card
- `Views::Focus` — one overdue task at a time, centered, with a complete button
- `Views::Calendar` — month grid with tasks on their due dates and overdue items stacked on today
- `Views::Agenda` — horizontal day columns, with overdue in a separate left column
- `Views::SeriesPanel` — the panel inner content, rendered as an HTML fragment for fetch

The existing `Dashboard` class gets refactored: panel logic moves into the shared layout, and the main column content becomes `TaskList`.

## Header nav

The header currently contains: `Ketchup` (left), `+ New`, and `username` (right).

It becomes: `Ketchup` (left), `List`, `Focus`, `Calendar`, `Agenda`, `+ New`, `username` (right).

The active view link gets bold weight or an underline, consistent with the existing minimal style. On mobile, view links collapse to an icon row or a dropdown — a detail left for implementation.

## Client-side panel

The panel div lives in every page's DOM, rendered by the layout, initially empty and closed. An Alpine component manages it:

```js
Alpine.data("panel", () => ({
  open: false,
  loading: false,

  async show(seriesId) {
    this.loading = true
    this.open = true
    const html = await fetch(`/series/${seriesId}/panel`).then(r => r.text())
    this.$refs.content.innerHTML = html
    this.loading = false
    initPanelEditors()
  },

  close() {
    this.open = false
    setTimeout(() => { this.$refs.content.innerHTML = "" }, 250)
  },
}))
```

`initPanelEditors()` extracts the existing imperative OverType/editor setup from `alpine:init` into a callable function. The same code runs after fragment injection rather than on page load.

Task cards in every view call `panel.show(seriesId)` on click.

## Scorecard integration

Three additions, none requiring a separate view:

- Inline streak indicators on task cards. Each task card in the list view gains a row of 5-6 dots (green for on-time, gray for missed) showing recent completion history. Rendered server-side from series history.
- Stats section in the series panel. Between the note and the history list, the panel shows streak count, on-time percentage, and a small dot or bar graph. Also server-rendered.
- Stats page (`/stats`) as a future addition, not part of this work.

## Focus view

Renders one overdue task at a time, sorted by urgency descending. The task name appears large and centered with its interval and overdue duration. The series note appears below in a subtle card. A large "Done" button submits the completion form.

Each completion is a form POST that redirects back to `/focus`. The next page load shows the next overdue task. When nothing remains overdue, the view shows "All caught up" briefly and redirects to `/`.

No client-side task advancement — each completion round-trips to the server, keeping the view in sync with reality.

## Calendar view

A month grid for the current month. Each day cell shows tasks due on that date as small colored pills (red for overdue, green for upcoming). All overdue tasks appear stacked on today's cell. Clicking a task pill opens the series panel.

Navigation arrows let the user move between months. Past months show only history; future months show scheduled tasks.

## Agenda view

Horizontal day columns spanning 7 days from today. A separate "Overdue" column sits on the left, styled with a red tint. Each column shows tasks due that day as colored pills. Clicking opens the series panel.

The day count (5, 7, 14) could be a user preference stored via Alpine Persist, but 7 days is sufficient for initial implementation.
