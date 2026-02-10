# Agents

Read the README for project context, domain concepts, and design intent.

## Layout

```
lib/
  config.rb        # Config Data object, reads DATABASE_URL from env
  db.rb            # Sequel connection + auto-migration
  web.rb           # Roda app (routes, current_user from Tailscale headers)
  views/
    layout.rb      # Phlex base layout
    series/
      new.rb       # New series form
db/
  migrate/         # Sequel migrations (numbered)
test/
  test_web.rb      # Minitest integration tests
public/
  css/             # Static assets
```

## Running

```sh
rake           # runs tests + binstubs (default)
rake test      # tests only
rake dev       # starts dev server with Tailscale serve + auto-restart via entr
```

Tests set `DATABASE_URL=:memory:` so they never touch the real database.

## Conventions

- **Views:** Phlex component classes under `lib/views/`, not ERB templates.
- **Migrations:** Sequel migrations in `db/migrate/`, numbered sequentially (`001_`, `002_`, …). Migrations auto-run on boot.
- **User identification:** Current user comes from `HTTP_TAILSCALE_USER_LOGIN` / `HTTP_TAILSCALE_USER_NAME` request headers.
- **Testing:** Minitest with `Rack::Test`. Fake Tailscale headers via helper.
