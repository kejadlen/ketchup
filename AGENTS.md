# Agents

Read the README for project context, domain concepts, and design intent.

## Layout

```
lib/
  ketchup/
    config.rb        # Config data object, reads DATABASE_URL from env
    db.rb            # Sequel connection + auto-migration
    models.rb        # User, Series, Task models and associations
    web.rb           # Roda app (routes, current_user from Tailscale headers)
    views/
      layout.rb      # Phlex base layout (head, nav, body wrapper)
      dashboard.rb   # Main view: overdue, upcoming, series detail/new sidebar
  sequel/
    plugins/
      sole.rb        # Custom Sequel plugin: Dataset#sole
db/
  migrate/           # Sequel migrations (numbered)
test/
  test_db.rb         # Schema constraint tests
  test_web.rb        # Minitest + Rack::Test integration tests
  test_sole.rb       # Sole plugin tests
public/
  js/app.js          # Alpine components, OverType editor setup
  css/               # Static stylesheets
config.ru            # Rack entrypoint (Sentry + Web.app)
```

## Running

```sh
rake           # runs tests + binstubs (default)
rake test      # tests only
rake dev       # starts dev server with Tailscale serve + auto-restart via entr
```

Tests set `DATABASE_URL=:memory:` so they never touch the real database.

## Conventions

- **Views:** Phlex component classes under `lib/ketchup/views/`, not ERB templates.
- **Migrations:** Sequel migrations in `db/migrate/`, numbered sequentially (`001_`, `002_`, …). Migrations auto-run on boot.
- **User identification:** Current user from `HTTP_TAILSCALE_USER_LOGIN` / `HTTP_TAILSCALE_USER_NAME` request headers.
- **Testing:** Minitest with `Rack::Test`. Fake Tailscale headers via helper.
- **Client-side:** Alpine.js for reactivity, Alpine Persist for state persistence, OverType for markdown editing. No build step — all loaded via CDN.
- **Ownership scoping:** User has `many_through_many :tasks` through `:series`. Routes use `@user.tasks_dataset` and `@user.series_dataset` to scope lookups.
