# Multi-View Dashboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let the user switch between four dashboard views (list, focus, calendar, agenda) with a shared client-side panel and scorecard integration.

**Architecture:** Four server-rendered Roda routes share a Layout that renders a view switcher in the header and an empty panel shell. Clicking a task fetches `/series/:id/panel` via JS and slides it open. Each view is a Phlex class. See `docs/plans/2026-02-17-multi-view-dashboard-design.md` for the full design.

**Tech Stack:** Ruby, Roda, Phlex, Alpine.js, OverType (no new dependencies)

---

### Task 1: Add `/series/:id/panel` endpoint and SeriesPanel view

The panel fragment endpoint is the foundation — everything else depends on fetching panel content via JS.

**Files:**
- Create: `lib/ketchup/views/series_panel.rb`
- Modify: `lib/ketchup/web.rb:92-100`
- Test: `test/test_web.rb`

**Step 1: Write the failing test**

Add to `test/test_web.rb`:

```ruby
def test_get_series_panel_returns_fragment
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: "2026-03-01")

  series = DB[:series].first
  get "/series/#{series[:id]}/panel", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "Call Mom"
  assert_includes last_response.body, "panel-inner"
  # Fragment — no <html>, no Layout wrapper
  refute_includes last_response.body, "<!DOCTYPE"
end

def test_get_series_panel_requires_own_series
  create_series(
    note: "Alice task", interval_unit: "day", interval_count: "1",
    first_due_date: "2026-03-01",
    headers: auth_headers(login: "alice@example.com")
  )

  series = DB[:series].first
  get "/series/#{series[:id]}/panel", {}, auth_headers(login: "bob@example.com")
  assert_equal 404, last_response.status
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test`
Expected: 2 failures (404 for panel route)

**Step 3: Create `SeriesPanel` view**

Create `lib/ketchup/views/series_panel.rb`. This is the existing `SeriesDetail` content but rendered as a standalone fragment (no Layout wrapper). For now, delegate to `SeriesDetail`:

```ruby
# frozen_string_literal: true

require "phlex"

require_relative "series_detail"

module Views
  class SeriesPanel < Phlex::HTML
    def initialize(series:, csrf: nil)
      @series = series
      @csrf = csrf
    end

    def view_template
      render SeriesDetail.new(series: @series, csrf: @csrf)
    end
  end
end
```

**Step 4: Add the route**

In `lib/ketchup/web.rb`, inside the `r.on Integer do |series_id|` block (after line 93), add a `panel` route before the `r.is` block:

```ruby
r.get "panel" do
  Views::SeriesPanel.new(series: @series, csrf: method(:csrf_token)).call
end
```

Also add `require_relative "views/series_panel"` near the top (after line 8).

**Step 5: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 6: Commit**

Message: `Add /series/:id/panel endpoint for fragment fetching`

---

### Task 2: Move panel shell into Layout, make it always present

The Layout currently has no panel markup. Dashboard renders the panel conditionally. Move the panel shell into Layout so every page gets it.

**Files:**
- Modify: `lib/ketchup/views/layout.rb:35-46`
- Modify: `lib/ketchup/views/dashboard.rb:21-64`
- Test: `test/test_web.rb`

**Step 1: Write the failing test**

Add to `test/test_web.rb`:

```ruby
def test_layout_includes_panel_shell
  get "/", {}, auth_headers
  assert_includes last_response.body, 'id="panel"'
  assert_includes last_response.body, 'x-data="panel"'
end
```

**Step 2: Run test to verify it fails**

Run: `rake test`
Expected: 1 failure (panel div not in root page without series selected)

**Step 3: Add panel shell to Layout**

In `lib/ketchup/views/layout.rb`, after the `yield` (line 42) and before `render_footer`, add the panel shell:

```ruby
div(
  id: "panel",
  class: "panel",
  "x-data": "panel",
  "x-bind:class": "open && 'panel--open'"
) do
  div(class: "panel-backdrop", "x-show": "open", "x-on:click": "close()")
  div(class: "panel-content", "x-ref": "content")
end
```

Remove the `panel_open` parameter from `Layout#initialize` and the `has-panel` body class logic (lines 7, 35) — the panel is now always present and managed by Alpine.

**Step 4: Remove panel rendering from Dashboard**

In `lib/ketchup/views/dashboard.rb`:
- Remove `render_panel` method entirely (lines 47-64)
- Remove `render_panel if has_panel` from `view_template` (line 26)
- Remove `has_panel` local variable (line 22-23)
- Simplify `view_template` to just render Layout + dashboard div + main column
- Remove `panel_open: has_panel` from Layout constructor call
- Keep `@series` in the initializer for now — it's still used for `selected_series` in TaskList

The Dashboard becomes:

```ruby
def view_template
  render Layout.new(current_user: @current_user) do
    div(class: "dashboard") do
      render_main_column
    end
  end
end
```

**Step 5: Update Layout to not accept panel_open**

Remove `panel_open` from `Layout#initialize` signature and the `@panel_open` instance variable. Remove the `has-panel` body class.

**Step 6: Fix existing tests**

The `test_get_series_shows_sidebar` test currently GETs `/series/:id` and expects panel content in the response. Since the panel is now client-side, this test needs updating. The `/series/:id` route should still render the dashboard page, but the panel content comes from a separate fetch. Update the route to pass a `data-open-series` attribute and update the test:

In `lib/ketchup/web.rb`, change the GET `/series/:id` handler to:

```ruby
r.get do
  Views::Dashboard.new(current_user: @user, series: @series, csrf: method(:csrf_token)).call
end
```

This still passes `series:` to Dashboard — but now it's only used for `selected_series` (highlighting the card), not for rendering the panel. Add a `data-open-series` attribute to the dashboard div so Alpine can auto-open the panel on page load.

In `dashboard.rb`, update `view_template`:

```ruby
def view_template
  render Layout.new(current_user: @current_user) do
    div(
      class: "dashboard",
      **(@series ? { "data-open-series": @series.id.to_s } : {})
    ) do
      render_main_column
    end
  end
end
```

Update `test_get_series_shows_sidebar` to test the new behavior:

```ruby
def test_get_series_shows_sidebar
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: "2026-03-01")

  series = DB[:series].first
  get "/series/#{series[:id]}", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "task-card--selected"
  assert_includes last_response.body, "data-open-series=\"#{series[:id]}\""
end
```

Also update `test_series_sidebar_has_new_link` — the "New" link and `href="/"` are no longer in the server-rendered panel. Remove or replace this test:

```ruby
def test_get_series_page_has_data_attribute
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: "2026-03-01")

  series = DB[:series].first
  get "/series/#{series[:id]}", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "data-open-series"
end
```

Update `test_get_series_shows_completed_history` — history is now served by the panel endpoint, not the full page. Move the history assertion to a panel test:

```ruby
def test_get_series_panel_shows_completed_history
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                first_due_date: "2026-03-01")

  task = DB[:tasks].first
  series = DB[:series].first
  csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers

  completed_task = DB[:tasks].first(id: task[:id])
  patch "/series/#{series[:id]}/tasks/#{completed_task[:id]}/note", { note: "Left a message" }, auth_headers

  get "/series/#{series[:id]}/panel", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "Left a message"
  assert_includes last_response.body, "task-history"
end
```

**Step 7: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 8: Commit**

Message: `Move panel shell into Layout, serve panel content via fragment fetch`

---

### Task 3: Client-side panel Alpine component

Update the Alpine `panel` component to fetch content from `/series/:id/panel` and extract OverType setup into a reusable `initPanelEditors()` function.

**Files:**
- Modify: `public/js/app.js:61-78` (panel component)
- Modify: `public/js/app.js:180-241` (OverType setup)

**Step 1: Update the Alpine panel component**

Replace the existing `panel` data component in `app.js` (lines 63-78) with:

```js
Alpine.data("panel", () => ({
  open: false,
  loading: false,

  init() {
    // Auto-open panel if server set data-open-series on the dashboard
    const dashboard = document.querySelector("[data-open-series]")
    if (dashboard) {
      const seriesId = dashboard.dataset.openSeries
      if (seriesId) this.show(seriesId)
    }
  },

  async show(seriesId) {
    this.loading = true
    this.open = true
    try {
      const resp = await fetch(`/series/${seriesId}/panel`)
      if (!resp.ok) return
      this.$refs.content.innerHTML = await resp.text()
      initPanelEditors(this.$refs.content)
    } finally {
      this.loading = false
    }
  },

  close() {
    this.open = false
    setTimeout(() => {
      if (this.$refs.content) this.$refs.content.innerHTML = ""
    }, 250)
  },
}))
```

**Step 2: Extract `initPanelEditors()`**

Move the imperative OverType setup for `#series-note-detail` (lines 181-225) into a function that takes a container element instead of searching the whole document. Place this before `alpine:init`:

```js
function initPanelEditors(container) {
  const noteDetail = container.querySelector("#series-note-detail")
  if (noteDetail) {
    const seriesId = noteDetail.dataset.seriesId
    const initialNote = noteDetail.dataset.value || ""

    const [editor] = new OverType(noteDetail, {
      value: initialNote,
      placeholder: "Series note...",
      autoResize: true,
      minHeight: 14,
      padding: "0 4px",
    })

    const resizeNote = compactOverType(noteDetail)

    const ta = noteDetail.querySelector("textarea")
    if (ta) {
      ta.style.pointerEvents = "none"
      ta.readOnly = true

      ta.addEventListener("blur", () => {
        const note = editor.getValue().trim()
        if (note === (initialNote || "").trim()) return
        saveSeriesField(seriesId, "note", note).then(() => location.reload())
      })

      container.addEventListener("start-editing", () => {
        ta.style.pointerEvents = ""
        ta.readOnly = false
        ta.focus()
        if (resizeNote) requestAnimationFrame(resizeNote)
      })

      container.addEventListener("stop-editing", () => {
        const note = editor.getValue().trim()
        if (note !== (initialNote || "").trim()) {
          saveSeriesField(seriesId, "note", note).then(() => location.reload())
          return
        }
        ta.style.pointerEvents = "none"
        ta.readOnly = true
        if (resizeNote) requestAnimationFrame(resizeNote)
      })
    }
  }
}
```

Remove the old inline `#series-note-detail` setup block from inside `alpine:init` (lines 180-225).

Keep the `#series-note-editor` setup (new series form) as-is — that lives on a standalone page, not in the panel.

**Step 3: Update task card links to use panel**

In `lib/ketchup/views/task_card.rb`, change the task name from a navigation link to a JS click handler. Replace line 28:

```ruby
a(href: "/series/#{@task[:series_id]}", class: "task-name") { name }
```

with:

```ruby
a(
  href: "/series/#{@task[:series_id]}",
  class: "task-name",
  "x-on:click.prevent": "document.querySelector('[x-data=\"panel\"]').__x.$data.show(#{@task[:series_id]})"
) { name }
```

Actually, a cleaner approach — dispatch a custom event that the panel listens for. Change the link to:

```ruby
a(
  href: "/series/#{@task[:series_id]}",
  class: "task-name",
  "x-on:click.prevent": "$dispatch('open-panel', { seriesId: #{@task[:series_id]} })"
) { name }
```

And in the panel's `init()`, add a listener:

```js
window.addEventListener("open-panel", (e) => {
  this.show(e.detail.seriesId)
})
```

The `href` remains as a fallback for middle-click/ctrl-click to open in a new tab.

**Step 4: Verify manually**

Run: `rake dev`
Navigate to `/`. Click a task name. The panel should slide open with the series detail fetched via JS. Click the backdrop to close.

**Step 5: Run tests**

Run: `rake test`
Expected: all pass (the task card test `test_task_card_links_to_series` still passes because the `href` attribute is preserved)

**Step 6: Commit**

Message: `Switch panel to client-side fetch, extract initPanelEditors`

---

### Task 4: Add view switcher to header nav

Add view navigation links to the Layout header. The active view is indicated by bold weight.

**Files:**
- Modify: `lib/ketchup/views/layout.rb:7,36-41`
- Modify: `lib/ketchup/views/dashboard.rb:23`
- Modify: `public/css/app.css`
- Test: `test/test_web.rb`

**Step 1: Write the failing test**

```ruby
def test_header_shows_view_nav
  get "/", {}, auth_headers
  assert_includes last_response.body, 'href="/"'
  assert_includes last_response.body, 'href="/focus"'
  assert_includes last_response.body, 'href="/calendar"'
  assert_includes last_response.body, 'href="/agenda"'
end

def test_header_highlights_active_view
  get "/", {}, auth_headers
  assert_includes last_response.body, "view-link--active"
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test`
Expected: 2 failures

**Step 3: Add `active_view` to Layout**

In `lib/ketchup/views/layout.rb`, add `active_view: :list` to `initialize`:

```ruby
def initialize(current_user:, title: "Ketchup", active_view: :list)
  @current_user = current_user
  @title = title
  @active_view = active_view
end
```

Update the nav in `view_template` (lines 38-41) to include view links:

```ruby
nav(class: "site-nav") do
  view_links.each do |path, label, view_key|
    a(
      href: path,
      class: ["view-link", ("view-link--active" if @active_view == view_key)]
    ) { label }
  end
  a(href: "/series/new", class: "header-action") { "+ New" }
  a(href: "/users/#{@current_user[:id]}", class: "header-user") { @current_user[:login] }
end
```

Add the private helper:

```ruby
def view_links
  [
    ["/", "List", :list],
    ["/focus", "Focus", :focus],
    ["/calendar", "Calendar", :calendar],
    ["/agenda", "Agenda", :agenda],
  ]
end
```

**Step 4: Add CSS for view links**

In `public/css/app.css`, after the `.header-action` styles (around line 66):

```css
.view-link {
  font-size: var(--step--1);
  color: #999;
  text-decoration: none;
}

.view-link:hover {
  color: #555;
}

.view-link--active {
  color: #1a1a1a;
  font-weight: 600;
}
```

**Step 5: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 6: Commit**

Message: `Add view switcher nav links to header`

---

### Task 5: Focus view and route

Add the focus view that shows one overdue task at a time.

**Files:**
- Create: `lib/ketchup/views/focus.rb`
- Modify: `lib/ketchup/web.rb`
- Modify: `lib/ketchup/web.rb:144-148` (complete redirect)
- Modify: `lib/ketchup/views/task_card.rb:16,19-21` (return_to field)
- Add CSS: `public/css/app.css`
- Test: `test/test_web.rb`

**Step 1: Write the failing tests**

```ruby
def test_focus_view_shows_overdue_task
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: (Date.today - 3).to_s)

  get "/focus", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "Call Mom"
  assert_includes last_response.body, "focus-task"
end

def test_focus_view_redirects_when_caught_up
  get "/focus", {}, auth_headers
  assert last_response.redirect?
  assert_includes last_response["Location"], "/"
end

def test_focus_view_shows_most_urgent_first
  create_series(note: "Low urgency", interval_unit: "month", interval_count: "1",
                first_due_date: (Date.today - 1).to_s)
  create_series(note: "High urgency", interval_unit: "day", interval_count: "1",
                first_due_date: (Date.today - 10).to_s)

  get "/focus", {}, auth_headers
  assert_includes last_response.body, "High urgency"
end

def test_complete_from_focus_redirects_to_focus
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: (Date.today - 3).to_s)

  task = DB[:tasks].first
  series = DB[:series].first
  csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete",
            { "return_to" => "/focus" }, auth_headers
  assert last_response.redirect?
  assert_equal "/focus", last_response["Location"]
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test`
Expected: 4 failures

**Step 3: Create the Focus view**

Create `lib/ketchup/views/focus.rb`:

```ruby
# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Focus < Phlex::HTML
    def initialize(current_user:, task:, csrf:, position:, total:)
      @current_user = current_user
      @task = task
      @csrf = csrf
      @position = position
      @total = total
    end

    def view_template
      render Layout.new(current_user: @current_user, active_view: :focus) do
        div(class: "focus-view") do
          render_progress
          render_task
          render_complete_button
        end
      end
    end

    private

    def render_progress
      div(class: "focus-progress") do
        plain "#{@position} of #{@total} overdue"
      end
    end

    def render_task
      name = @task[:note].lines.first&.strip || @task[:note]
      interval_count = @task[:interval_count] || @task.series.interval_count
      interval_unit = @task[:interval_unit] || @task.series.interval_unit
      interval = "#{interval_count} #{interval_count == 1 ? interval_unit : "#{interval_unit}s"}"

      div(class: "focus-task") do
        div(class: "focus-urgency") do
          plain "#{format("%.1f", @task.urgency)}× overdue"
        end
        h1(class: "focus-name") { name }
        p(class: "focus-interval") { "every #{interval}" }
      end
    end

    def render_complete_button
      complete_path = "/series/#{@task[:series_id]}/tasks/#{@task[:id]}/complete"
      form(method: "post", action: complete_path, class: "focus-form") do
        input(type: "hidden", name: "_csrf", value: @csrf.call(complete_path))
        input(type: "hidden", name: "return_to", value: "/focus")
        button(type: "submit", class: "focus-complete-btn") do
          span { "✓" }
          plain " Done"
        end
      end
    end
  end
end
```

**Step 4: Add the route**

In `lib/ketchup/web.rb`, add `require_relative "views/focus"` at the top.

Add the focus route after `r.root` (after line 42):

```ruby
r.get "focus" do
  overdue = @user.overdue_tasks.all.sort_by { |t| -t.urgency }
  if overdue.empty?
    r.redirect "/"
  else
    Views::Focus.new(
      current_user: @user,
      task: overdue.first,
      csrf: method(:csrf_token),
      position: 1,
      total: overdue.size
    ).call
  end
end
```

**Step 5: Add `return_to` support to the complete handler**

In `lib/ketchup/web.rb`, update the complete handler (around line 144-148):

```ruby
r.post "complete" do
  r.halt 422 unless @task[:completed_at].nil?
  @task.complete!(today: Date.today)

  return_to = r.params["return_to"]
  if return_to && return_to.start_with?("/")
    r.redirect return_to
  else
    r.redirect "/series/#{series_id}"
  end
end
```

The `start_with?("/")` check prevents open redirect.

**Step 6: Add `return_to` hidden field to TaskCard**

In `lib/ketchup/views/task_card.rb`, add a `return_to:` parameter to `initialize`:

```ruby
def initialize(task:, csrf:, selected: false, overdue: false, return_to: nil)
  @task = task
  @csrf = csrf
  @selected = selected
  @overdue = overdue
  @return_to = return_to
end
```

In the form (line 19-25), add after the CSRF hidden input:

```ruby
input(type: "hidden", name: "return_to", value: @return_to) if @return_to
```

**Step 7: Add focus view CSS**

In `public/css/app.css`:

```css
/* -------------------- */
/* Focus view */
/* -------------------- */

.focus-view {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  flex: 1;
  padding: var(--space-xl) var(--space-m);
  text-align: center;
}

.focus-progress {
  font-size: var(--step--1);
  color: #999;
  margin-bottom: var(--space-l);
}

.focus-task {
  margin-bottom: var(--space-l);
}

.focus-urgency {
  font-size: var(--step--2);
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #c0392b;
  margin-bottom: var(--space-2xs);
}

.focus-name {
  font-size: var(--step-3);
  font-weight: 700;
  line-height: 1.2;
  margin-bottom: var(--space-3xs);
}

.focus-interval {
  font-size: var(--step-0);
  color: #888;
}

.focus-form {
  display: inline-flex;
}

.focus-complete-btn {
  all: unset;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: var(--space-2xs);
  padding: var(--space-xs) var(--space-xl);
  background: #1a1a1a;
  color: #fff;
  border-radius: 99px;
  font-size: var(--step-1);
  font-weight: 600;
  transition: background 0.15s;
}

.focus-complete-btn:hover {
  background: #333;
}
```

**Step 8: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 9: Commit**

Message: `Add focus view for processing overdue tasks one at a time`

---

### Task 6: Calendar view and route

**Files:**
- Create: `lib/ketchup/views/calendar.rb`
- Modify: `lib/ketchup/web.rb`
- Add CSS: `public/css/app.css`
- Test: `test/test_web.rb`

**Step 1: Write the failing tests**

```ruby
def test_calendar_view_renders
  get "/calendar", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "calendar-grid"
end

def test_calendar_shows_tasks_on_due_date
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: Date.today.to_s)

  get "/calendar", {}, auth_headers
  assert_includes last_response.body, "Call Mom"
end

def test_calendar_view_highlights_active
  get "/calendar", {}, auth_headers
  assert_includes last_response.body, "view-link--active"
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test`
Expected: 3 failures

**Step 3: Create the Calendar view**

Create `lib/ketchup/views/calendar.rb`:

```ruby
# frozen_string_literal: true

require "phlex"
require "date"

require_relative "layout"

module Views
  class Calendar < Phlex::HTML
    def initialize(current_user:, csrf:, date: Date.today)
      @current_user = current_user
      @csrf = csrf
      @date = date
    end

    def view_template
      first_of_month = Date.new(@date.year, @date.month, 1)
      last_of_month = Date.new(@date.year, @date.month, -1)
      prev_month = first_of_month << 1
      next_month = first_of_month >> 1

      overdue = @current_user.overdue_tasks.all
      upcoming = @current_user.upcoming_tasks
        .where { due_date <= last_of_month }
        .all

      tasks_by_date = {}
      overdue.each { |t| (tasks_by_date[Date.today] ||= []) << [t, true] }
      upcoming.each { |t| (tasks_by_date[t[:due_date]] ||= []) << [t, false] }

      render Layout.new(current_user: @current_user, active_view: :calendar) do
        div(class: "calendar-view") do
          div(class: "calendar-header") do
            a(href: "/calendar?date=#{prev_month}", class: "calendar-nav") { "←" }
            h2(class: "calendar-month-title") { first_of_month.strftime("%B %Y") }
            a(href: "/calendar?date=#{next_month}", class: "calendar-nav") { "→" }
          end

          div(class: "calendar-grid") do
            %w[Mon Tue Wed Thu Fri Sat Sun].each do |day_name|
              div(class: "calendar-day-name") { day_name }
            end

            start_dow = (first_of_month.wday - 1) % 7
            start_dow.times { div(class: "calendar-day calendar-day--empty") }

            (1..last_of_month.day).each do |day_num|
              date = Date.new(@date.year, @date.month, day_num)
              is_today = date == Date.today
              day_tasks = tasks_by_date[date] || []

              div(class: ["calendar-day", ("calendar-day--today" if is_today)]) do
                span(class: "calendar-day-num") { day_num.to_s }
                day_tasks.each do |task, is_overdue|
                  task_name = task[:note].lines.first&.strip || task[:note]
                  a(
                    href: "/series/#{task[:series_id]}",
                    class: ["calendar-pill", ("calendar-pill--overdue" if is_overdue)],
                    "x-on:click.prevent": "$dispatch('open-panel', { seriesId: #{task[:series_id]} })"
                  ) { task_name }
                end
              end
            end
          end
        end
      end
    end
  end
end
```

**Step 4: Add the route**

In `lib/ketchup/web.rb`, add `require_relative "views/calendar"` at the top.

Add after the focus route:

```ruby
r.get "calendar" do
  date = begin
           Date.parse(r.params["date"].to_s)
         rescue Date::Error
           Date.today
         end
  Views::Calendar.new(current_user: @user, csrf: method(:csrf_token), date: date).call
end
```

**Step 5: Add calendar CSS**

In `public/css/app.css`:

```css
/* -------------------- */
/* Calendar view */
/* -------------------- */

.calendar-view {
  padding: var(--space-m) var(--space-m);
  max-width: 56rem;
  margin: 0 auto;
}

.calendar-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-s);
}

.calendar-month-title {
  font-size: var(--step-1);
  font-weight: 700;
}

.calendar-nav {
  font-size: var(--step-0);
  color: #555;
  text-decoration: none;
  padding: var(--space-3xs) var(--space-2xs);
  border-radius: 4px;
}

.calendar-nav:hover {
  background: #f5f5f5;
}

.calendar-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 2px;
}

.calendar-day-name {
  text-align: center;
  font-size: var(--step--2);
  font-weight: 600;
  color: #999;
  padding: var(--space-3xs);
}

.calendar-day {
  min-height: 5rem;
  padding: var(--space-3xs);
  border: 1px solid #eee;
  border-radius: 4px;
  overflow: hidden;
}

.calendar-day--empty {
  background: #fafafa;
  border-color: transparent;
}

.calendar-day--today {
  background: #f0f7ff;
  border-color: #4a90d9;
  border-width: 2px;
}

.calendar-day-num {
  font-size: var(--step--2);
  font-weight: 400;
  color: #555;
  display: block;
  margin-bottom: 2px;
}

.calendar-day--today .calendar-day-num {
  font-weight: 700;
  color: #4a90d9;
}

.calendar-pill {
  display: block;
  font-size: 10px;
  padding: 1px 4px;
  background: #e8f5e9;
  color: #2e7d32;
  border-radius: 3px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-top: 1px;
  text-decoration: none;
  cursor: pointer;
}

.calendar-pill--overdue {
  background: #fde8e6;
  color: #c0392b;
}
```

**Step 6: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 7: Commit**

Message: `Add calendar month view`

---

### Task 7: Agenda view and route

**Files:**
- Create: `lib/ketchup/views/agenda.rb`
- Modify: `lib/ketchup/web.rb`
- Add CSS: `public/css/app.css`
- Test: `test/test_web.rb`

**Step 1: Write the failing tests**

```ruby
def test_agenda_view_renders
  get "/agenda", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "agenda-view"
end

def test_agenda_shows_overdue_column
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                first_due_date: (Date.today - 3).to_s)

  get "/agenda", {}, auth_headers
  assert_includes last_response.body, "Call Mom"
  assert_includes last_response.body, "agenda-overdue"
end

def test_agenda_shows_upcoming_on_day
  create_series(note: "Haircut", interval_unit: "week", interval_count: "6",
                first_due_date: Date.today.to_s)

  get "/agenda", {}, auth_headers
  assert_includes last_response.body, "Haircut"
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test`
Expected: 3 failures

**Step 3: Create the Agenda view**

Create `lib/ketchup/views/agenda.rb`:

```ruby
# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Agenda < Phlex::HTML
    DAYS = 7

    def initialize(current_user:, csrf:)
      @current_user = current_user
      @csrf = csrf
    end

    def view_template
      today = Date.today
      dates = (0...DAYS).map { |i| today + i }
      end_date = dates.last

      overdue = @current_user.overdue_tasks.all.sort_by { |t| -t.urgency }
      upcoming = @current_user.upcoming_tasks
        .where { due_date <= end_date }
        .all

      tasks_by_date = {}
      upcoming.each { |t| (tasks_by_date[t[:due_date]] ||= []) << t }

      render Layout.new(current_user: @current_user, active_view: :agenda) do
        div(class: "agenda-view") do
          div(class: "agenda-columns") do
            render_overdue_column(overdue)
            dates.each_with_index do |date, i|
              render_day_column(date, tasks_by_date[date] || [], i == 0)
            end
          end
        end
      end
    end

    private

    def render_overdue_column(tasks)
      div(class: "agenda-column agenda-overdue") do
        div(class: "agenda-column-header agenda-column-header--overdue") { "Overdue" }
        if tasks.empty?
          p(class: "empty") { "All clear" }
        else
          tasks.each { |t| render_task_pill(t, overdue: true) }
        end
      end
    end

    def render_day_column(date, tasks, is_today)
      label = if is_today
                "Today"
              elsif date == Date.today + 1
                "Tomorrow"
              else
                date.strftime("%a %-d")
              end

      div(class: ["agenda-column", ("agenda-column--today" if is_today)]) do
        div(class: "agenda-column-header") { label }
        tasks.each { |t| render_task_pill(t, overdue: false) }
      end
    end

    def render_task_pill(task, overdue:)
      name = task[:note].lines.first&.strip || task[:note]
      a(
        href: "/series/#{task[:series_id]}",
        class: ["agenda-pill", ("agenda-pill--overdue" if overdue)],
        "x-on:click.prevent": "$dispatch('open-panel', { seriesId: #{task[:series_id]} })"
      ) { name }
    end
  end
end
```

**Step 4: Add the route**

In `lib/ketchup/web.rb`, add `require_relative "views/agenda"` at the top.

Add after the calendar route:

```ruby
r.get "agenda" do
  Views::Agenda.new(current_user: @user, csrf: method(:csrf_token)).call
end
```

**Step 5: Add agenda CSS**

In `public/css/app.css`:

```css
/* -------------------- */
/* Agenda view */
/* -------------------- */

.agenda-view {
  padding: var(--space-m);
  overflow-x: auto;
}

.agenda-columns {
  display: grid;
  grid-template-columns: 120px repeat(7, 1fr);
  gap: 2px;
  min-width: 640px;
}

.agenda-column {
  background: #fff;
  border: 1px solid #eee;
  border-radius: 4px;
  padding: var(--space-3xs);
  min-height: 12rem;
}

.agenda-column--today {
  background: #f0f7ff;
  border-color: #4a90d9;
}

.agenda-overdue {
  background: #fefafa;
  border-color: #f0e0de;
}

.agenda-column-header {
  font-size: var(--step--2);
  font-weight: 600;
  color: #888;
  text-align: center;
  padding: var(--space-3xs);
  margin-bottom: var(--space-3xs);
}

.agenda-column-header--overdue {
  color: #c0392b;
}

.agenda-pill {
  display: block;
  font-size: var(--step--2);
  padding: 3px 6px;
  background: #e8f5e9;
  color: #2e7d32;
  border-radius: 4px;
  margin-bottom: 3px;
  text-decoration: none;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  cursor: pointer;
}

.agenda-pill--overdue {
  background: #fde8e6;
  color: #c0392b;
  font-weight: 600;
}
```

**Step 6: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 7: Commit**

Message: `Add agenda week view with overdue column`

---

### Task 8: Scorecard data in series panel

Add streak count and on-time percentage to the series detail panel.

**Files:**
- Modify: `lib/ketchup/models.rb` (add `Series#completion_stats`)
- Modify: `lib/ketchup/views/series_detail.rb:91-92`
- Test: `test/test_web.rb`

**Step 1: Write the failing test**

```ruby
def test_series_panel_shows_stats
  create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                first_due_date: (Date.today - 7).to_s)

  series = DB[:series].first
  task = DB[:tasks].first
  csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers

  get "/series/#{series[:id]}/panel", {}, auth_headers
  assert_includes last_response.body, "panel-stats"
end
```

**Step 2: Run test to verify it fails**

Run: `rake test`
Expected: 1 failure

**Step 3: Add `completion_stats` to Series model**

In `lib/ketchup/models.rb`, add to the `Series` class:

```ruby
def completion_stats
  completed = completed_tasks
  return { streak: 0, on_time_pct: 100, total: 0 } if completed.empty?

  streak = 0
  on_time = 0
  completed.each_with_index do |t, i|
    on_time += 1 if t[:completed_at].to_date <= t[:due_date]
    streak += 1 if i == streak && t[:completed_at].to_date <= t[:due_date]
  end

  { streak: streak, on_time_pct: (on_time * 100.0 / completed.size).round, total: completed.size }
end
```

**Step 4: Render stats in SeriesDetail**

In `lib/ketchup/views/series_detail.rb`, before the history section (line 92, `unless @series.completed_tasks.empty?`), add:

```ruby
unless @series.completed_tasks.empty?
  stats = @series.completion_stats
  div(class: "panel-stats") do
    dl(class: "detail-fields") do
      dt { "Streak" }
      dd { stats[:streak].to_s }
      dt { "On-time" }
      dd { "#{stats[:on_time_pct]}%" }
    end
  end
```

Merge this with the existing `unless @series.completed_tasks.empty?` block — compute stats at the top of the block, render the stats div before the history heading.

**Step 5: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 6: Commit**

Message: `Add completion stats (streak, on-time rate) to series panel`

---

### Task 9: Clean up and remove old panel code paths

Remove the `panel:` parameter from Dashboard, simplify the `/users/:id` and `/series/:id` GET routes now that the panel is client-side.

**Files:**
- Modify: `lib/ketchup/views/dashboard.rb:14`
- Modify: `lib/ketchup/web.rb:47-49`
- Test: `test/test_web.rb`

**Step 1: Review what's left**

The `/users/:id` GET route currently passes `panel: :user` to Dashboard. Since the panel is now client-side, this route should render the dashboard with a `data-open-user` attribute instead, or simply redirect to `/?panel=user`, or serve the user form via the panel fetch pattern.

For consistency, add a `/users/:id/panel` endpoint (like series) and handle user settings the same way — click the username in the header, fetch the user panel via JS.

**Step 2: Add user panel endpoint**

Add to `test/test_web.rb`:

```ruby
def test_get_user_panel_returns_fragment
  get "/", {}, auth_headers  # create user
  user_id = DB[:users].first(login: "alice@example.com")[:id]

  get "/users/#{user_id}/panel", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "alice@example.com"
  refute_includes last_response.body, "<!DOCTYPE"
end
```

In `lib/ketchup/web.rb`, add a panel route inside the users block:

```ruby
r.get "panel" do
  Views::UserForm.new(current_user: @user, csrf: method(:csrf_token)).call
end
```

Update the `/users/:id` GET to render Dashboard without `panel:` and with a `data-open-user` attribute (similar to `data-open-series`).

**Step 3: Remove `panel:` from Dashboard**

Remove the `panel` parameter from `Dashboard#initialize`. Remove any remaining references to `@panel`.

**Step 4: Update existing user tests**

Update `test_get_user_shows_email_form` to test the panel endpoint instead:

```ruby
def test_get_user_panel_shows_email_form
  get "/", {}, auth_headers
  user_id = DB[:users].first(login: "alice@example.com")[:id]

  get "/users/#{user_id}/panel", {}, auth_headers
  assert last_response.ok?
  assert_includes last_response.body, "alice@example.com"
  assert_includes last_response.body, 'name="email"'
end
```

**Step 5: Run tests to verify they pass**

Run: `rake test`
Expected: all pass

**Step 6: Commit**

Message: `Add user panel endpoint, remove server-rendered panel from Dashboard`
