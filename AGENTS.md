# Agents

Read the README for project context, domain concepts, and design intent.

The [project backlog](https://github.com/users/kejadlen/projects/5/views/1) tracks planned work.

## GitHub references

| Resource     | ID                       |
|--------------|--------------------------|
| Repository   | `R_kgDORQBlMg`           |
| Project      | `PVT_kwHNIb_OAT0x9g`    |
| Status field | `PVTSSF_lAHNIb_OAT0x9s4Pb9Ml` |

Status options: Backlog (`f75ad846`), In Progress (`47fc9ee4`), Done (`98236657`), Icebox (`82312985`).

```sh
gh issue list --repo kejadlen/ketchup                # list open issues
gh issue view 22 --repo kejadlen/ketchup             # read an issue
gh issue create --repo kejadlen/ketchup --title "…"  # create an issue
gh project item-list 5 --owner kejadlen              # list backlog items
gh project item-add 5 --owner kejadlen --url <url>   # add an issue to the board
```

## Layout

```
lib/
  ketchup/
    config.rb        # Config data object, reads DATABASE_URL from env
    db.rb            # Sequel connection + auto-migration
    models.rb        # User, Series, Task models and associations
    seed.rb          # Seed.call(user:, series:) — creates series, tasks, and history
    snapshots.rb     # Ferrum-driven headless screenshot capture
    web.rb           # Roda app (routes, current_user from Tailscale headers)
    views/
      layout.rb      # Phlex base layout (head, nav, body wrapper)
      dashboard.rb   # Main view: overdue, upcoming, series detail/new sidebar
      series/
        new.rb       # Standalone new-series form page
  sequel/
    plugins/
      sole.rb        # Custom Sequel plugin: Dataset#sole
db/
  migrate/           # Sequel migrations (numbered)
test/
  test_db.rb         # Schema constraint tests
  test_web.rb        # Minitest + Rack::Test integration tests
  test_sole.rb       # Sole plugin tests
  test_seed.rb       # Seed module tests
templates/           # ERB templates for snapshot diff and gallery viewers
public/
  js/app.js          # Alpine components, OverType editor setup
  css/               # Static stylesheets
config.ru            # Rack entrypoint (Sentry + Web.app)
```

## Running

```sh
rake                    # runs tests, type checking, and binstubs (default)
rake test               # tests only (use this to run tests, not ruby directly)
rake check              # rbs-inline + steep check
rake dev                # starts dev server with Tailscale serve + auto-restart via entr
rake seed               # seeds database with sample series and tasks
rake snapshots:capture  # headless Chrome screenshots of key app states
rake snapshots:diff     # compare current screenshots against latest release baseline
rake snapshots:review   # capture, diff, and open in browser
rake snapshots:gallery  # generate an HTML gallery of screenshots
```

Binstubs are installed to `.direnv/`, which direnv adds to `$PATH`. **Never use `bundle exec`** — run commands directly (`rake`, `rbs-inline`, `steep`, etc.).

Tests set `DATABASE_URL=:memory:` so they never touch the real database.

## Snapshots

Headless Chrome screenshots for visual review after UI changes. `Capture#run_capture` in `lib/ketchup/snapshots.rb` scripts a browser session against an in-memory database — no real data is touched.

Run `rake snapshots:review` to capture screenshots and open a side-by-side diff against the baseline from the latest GitHub release. CI uploads new baselines on each push to main.

To add a snapshot, add a `snap("name")` call in `run_capture`. Pass a block for navigation before the screenshot, or `selector:` to capture a single element instead of the full page:

```ruby
snap("my-state") do
  goto @base
  wait_for(".some-element")
end

snap("just-sidebar", selector: ".column-aside")
```

Output goes to `~/.cache/ketchup/snapshots/` (or `$XDG_CACHE_HOME`). Templates for the diff and gallery viewers live in `templates/`.

## Conventions

- **Views:** Phlex component classes under `lib/ketchup/views/`, not ERB templates.
- **Migrations:** Sequel migrations in `db/migrate/`, numbered sequentially (`001_`, `002_`, …). Migrations auto-run on boot.
- **User identification:** Current user from `HTTP_TAILSCALE_USER_LOGIN` / `HTTP_TAILSCALE_USER_NAME` request headers.
- **Testing:** Minitest with `Rack::Test`. Fake Tailscale headers via helper.
- **Client-side:** Alpine.js for reactivity, Alpine Persist for state persistence, OverType for markdown editing. No build step — all loaded via CDN.
- **Ownership scoping:** User has `many_through_many :tasks` through `:series`. Routes use `@user.tasks_dataset` and `@user.series_dataset` to scope lookups.
