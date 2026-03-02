# Ketchup Module Extraction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all application classes and constants under a `Ketchup` module.

**Architecture:** Wrap each source file's definitions in `module Ketchup ... end`. Ruby's constant lookup resolves unqualified references within the enclosing module, so internal cross-references (e.g., `User` from `Web`, `CONFIG` from `Layout`) continue to work without explicit `Ketchup::` prefixes. Only files outside the module (config.ru, Rakefile, tests) need their references qualified.

**Tech Stack:** Ruby, Sequel, Roda, Phlex, Minitest

---

## Key insight

Files already inside `module Ketchup` (dev_auth.rb, seed.rb, snapshots.rb) reference top-level constants like `User`, `Series`, `Task`, `Web`, `DB`, `CONFIG`. Once those constants move into `module Ketchup`, Ruby's constant lookup finds them in the enclosing module first. So these files need *no reference changes at all* — the resolution shifts automatically.

Likewise, files that get newly wrapped in `module Ketchup` keep their internal references unchanged.

The only reference updates are in top-level files: `config.ru`, `Rakefile`, and `test/*.rb`.

## Sequel model table names

Sequel derives table names from the last segment of the class name. `Ketchup::User` maps to `users`, `Ketchup::Series` to `series`, `Ketchup::Task` to `tasks`. No `set_dataset` calls needed.

## DB escape hatch

If Sequel rejects `Ketchup::DB` anywhere (plugin registration, migration context), restore `DB` as a top-level constant. That means removing the `module Ketchup` wrapper from `db.rb` only, and replacing `Ketchup::DB` with `DB` in config.ru, Rakefile, and tests. The lib/ files that are inside `module Ketchup` would need a top-level `DB` reference, which Ruby resolves by falling through to the top-level constant.

---

### Task 1: Wrap core modules (config.rb, db.rb)

**Files:**
- Modify: `lib/ketchup/config.rb`
- Modify: `lib/ketchup/db.rb`

**Step 1: Wrap config.rb**

Add `module Ketchup` around all definitions. The file currently defines `Config` (Data class) and `CONFIG` constant at top level. Wrap them:

```ruby
# rbs_inline: enabled
# frozen_string_literal: true

require "securerandom"

module Ketchup
  Config = Data.define(
    :database_url,   #: String
    :session_secret, #: String
    :auth_header,    #: String
    :sentry,         #: SentryConfig?
    :otel,           #: OtelConfig?
    :default_user,   #: String?
    :commit_sha,     #: String?
    :change_id,      #: String?
    :build_date,     #: String?
  )

  class Config
    SentryConfig = Data.define(
      :dsn, #: String
      :env, #: String?
    )

    OtelConfig = Data.define(
      :endpoint, #: String
    )

    #: () -> String
    def to_s
      parts = ["database=#{database_url}"]
      parts << "auth=#{auth_header}"
      parts << "sentry=#{sentry.env || "on"}" if sentry
      parts << "otel=on" if otel
      parts << "default_user=#{default_user}" if default_user
      parts << "commit=#{commit_sha}" if commit_sha
      parts << "change=#{change_id}" if change_id
      parts << "built=#{build_date}" if build_date
      "Config(#{parts.join(", ")})"
    end

    #: (?Hash[String, String] env) -> Config
    def self.from_env(env = ENV)
      sentry_dsn = env["SENTRY_DSN"]
      otel_endpoint = env["OTEL_EXPORTER_OTLP_ENDPOINT"]
      new(
        database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" },
        session_secret: env.fetch("SESSION_SECRET") { SecureRandom.hex(64) },
        auth_header: env.fetch("AUTH_HEADER", "Remote-User"),
        sentry: sentry_dsn ? SentryConfig.new(dsn: sentry_dsn, env: env["SENTRY_ENV"]) : nil,
        otel: otel_endpoint ? OtelConfig.new(endpoint: otel_endpoint) : nil,
        default_user: env["DEFAULT_USER"],
        commit_sha: env["COMMIT_SHA"],
        change_id: env["CHANGE_ID"]&.slice(0, 8),
        build_date: env["BUILD_DATE"]
      )
    end
  end

  CONFIG = Config.from_env
end
```

**Step 2: Wrap db.rb**

The file defines `DB` and runs migrations. `CONFIG` resolves within `module Ketchup`:

```ruby
# frozen_string_literal: true

require "sequel"

require_relative "config"

module Ketchup
  DB = Sequel.sqlite(CONFIG.database_url)
  Sequel.extension :migration
  Sequel::Migrator.run(DB, File.expand_path("../../db/migrate", __dir__))
end
```

---

### Task 2: Wrap models.rb

**Files:**
- Modify: `lib/ketchup/models.rb`

**Step 1: Wrap models.rb**

The Sequel plugin calls (`Sequel::Model.plugin`) are global configuration — they work inside or outside the module. `DB` resolves to `Ketchup::DB` within the module. Model cross-references (`Series`, `Task`, `User`) resolve within the module.

```ruby
# frozen_string_literal: true

require_relative "db"

module Ketchup
  Sequel::Model.plugin :timestamps, update_on_create: true
  Sequel::Model.plugin :sole
  Sequel::Model.plugin :many_through_many

  class User < Sequel::Model
    one_to_many :series
    many_through_many :tasks, [[:series, :user_id, :id]], right_primary_key: :series_id

    def active_tasks
      tasks_dataset
        .where(completed_at: nil)
        .select_all(:tasks)
        .select_append(
          Sequel[:series][:note],
          Sequel[:series][:interval_unit],
          Sequel[:series][:interval_count]
        )
    end

    def overdue_tasks
      active_tasks.where { due_date < Date.today }
    end

    def upcoming_tasks
      active_tasks.where { due_date >= Date.today }.order(:due_date)
    end
  end

  class Series < Sequel::Model
    many_to_one :user
    one_to_many :tasks

    INTERVAL_UNITS = %w[day week month quarter year].freeze

    def active_task
      tasks_dataset.where(completed_at: nil).first
    end

    def completed_tasks
      tasks_dataset
        .exclude(completed_at: nil)
        .order(Sequel.desc(:completed_at))
        .select(:id, :due_date, :completed_at, :note)
        .all
    end

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

    def next_due_date(completed_on)
      case interval_unit
      when "day"
        completed_on + interval_count
      when "week"
        completed_on + (7 * interval_count)
      when "month"
        completed_on >> interval_count
      when "quarter"
        completed_on >> (3 * interval_count)
      when "year"
        completed_on >> (12 * interval_count)
      else
        fail
      end
    end

    def self.create_with_first_task(user:, note:, interval_unit:, interval_count:, first_due_date:)
      DB.transaction do
        series = create(
          user_id: user.id,
          note: note,
          interval_unit: interval_unit,
          interval_count: interval_count
        )

        Task.create(
          series_id: series.id,
          due_date: first_due_date
        )

        series
      end
    end
  end

  class Task < Sequel::Model
    many_to_one :series

    INTERVAL_DAYS = {
      "day" => 1, "week" => 7, "month" => 30, "quarter" => 91, "year" => 365
    }.freeze

    def urgency
      days_overdue = Date.today - self[:due_date]
      return 0 if days_overdue <= 0

      count = self[:interval_count] || series.interval_count
      unit = self[:interval_unit] || series.interval_unit
      interval = count * INTERVAL_DAYS.fetch(unit)
      days_overdue.to_f / interval
    end

    def complete!(completed_on:)
      DB.transaction do
        update(completed_at: Time.new(completed_on.year, completed_on.month, completed_on.day))
        Task.create(series_id: series.id, due_date: series.next_due_date(completed_on))
      end
    end

    def undo_complete!
      DB.transaction do
        next_task = series.active_task
        next_task.destroy if next_task
        update(completed_at: nil)
      end
    end
  end
end
```

---

### Task 3: Wrap views

**Files:**
- Modify: `lib/ketchup/views/layout.rb`
- Modify: `lib/ketchup/views/dashboard.rb`
- Modify: `lib/ketchup/views/task_card.rb`
- Modify: `lib/ketchup/views/series/new.rb`
- Modify: `lib/ketchup/views/series/show.rb`
- Modify: `lib/ketchup/views/user/show.rb`

**Step 1: Wrap each view file in `module Ketchup`**

Add `module Ketchup` as the outermost wrapper. The existing `module Views` nesting stays. Internal references (`CONFIG` in layout, `Series::INTERVAL_UNITS` in dashboard, `Layout` / `TaskCard` cross-refs) all resolve within `module Ketchup`.

For each file, the change is identical: add `module Ketchup` after the requires/frozen_string_literal and indent the existing code one level, then close with `end`.

layout.rb:
```ruby
# frozen_string_literal: true

require "digest"
require "phlex"

module Ketchup
  module Views
    # ... existing Layout class unchanged ...
  end
end
```

dashboard.rb:
```ruby
# frozen_string_literal: true

require "phlex"

require_relative "layout"
require_relative "task_card"

module Ketchup
  module Views
    INTERVAL_OPTIONS = Series::INTERVAL_UNITS.map { |u| [u, "#{u}(s)"] }.freeze

    AGENDA_DAYS = 7

    class Dashboard < Phlex::HTML
      # ... existing code unchanged ...
    end
  end
end
```

task_card.rb, series/new.rb, series/show.rb, user/show.rb: same pattern — wrap existing `module Views` in `module Ketchup`.

---

### Task 4: Wrap web.rb

**Files:**
- Modify: `lib/ketchup/web.rb`

**Step 1: Wrap web.rb**

`CONFIG`, `User`, `Series`, `Task`, `DB`, `Views::*` all resolve within `module Ketchup`:

```ruby
# frozen_string_literal: true

require "json"
require "roda"

require_relative "models"
require_relative "views/dashboard"
require_relative "views/series/new"
require_relative "views/series/show"
require_relative "views/user/show"

module Ketchup
  class Web < Roda
    # ... existing code unchanged ...
  end
end
```

---

### Task 5: Update config.ru

**Files:**
- Modify: `config.ru`

**Step 1: Update all references from top-level to `Ketchup::`**

Replace:
- `CONFIG` → `Ketchup::CONFIG` (6 occurrences)
- `Web` → `Ketchup::Web` (1 occurrence, last line)
- `User` → `Ketchup::User` (1 occurrence)

`Ketchup::DevAuth` and `Ketchup::Seed` references already use the `Ketchup::` prefix — no change.

---

### Task 6: Update Rakefile

**Files:**
- Modify: `Rakefile`

**Step 1: Update references in `seed` task**

Replace:
- `DB[:tasks]` → `Ketchup::DB[:tasks]`
- `DB[:series]` → `Ketchup::DB[:series]`
- `User.first` → `Ketchup::User.first`

The `Ketchup::Seed` and `Ketchup::Snapshots` references already use the `Ketchup::` prefix — no change needed.

---

### Task 7: Update tests

**Files:**
- Modify: `test/test_web.rb`
- Modify: `test/test_db.rb`
- Modify: `test/test_seed.rb`
- Modify: `test/test_sole.rb`

**Step 1: Update test_web.rb**

Replace:
- `Web.app` → `Ketchup::Web.app`
- `DB[` → `Ketchup::DB[` (all occurrences)
- `Task.first` → `Ketchup::Task.first`
- `Task.where` → `Ketchup::Task.where`

**Step 2: Update test_db.rb**

Replace:
- `DB[` → `Ketchup::DB[`

**Step 3: Update test_seed.rb**

Replace:
- `User.create` → `Ketchup::User.create`
- `Series.count` → `Ketchup::Series.count`
- `Task.count` → `Ketchup::Task.count`
- `Series.first` → `Ketchup::Series.first`
- `Task.first` → `Ketchup::Task.first`
- `Task.exclude` → `Ketchup::Task.exclude`

`Ketchup::Seed` already uses the `Ketchup::` prefix — no change.

**Step 4: Update test_sole.rb**

Replace:
- `User.create` → `Ketchup::User.create`
- `User.where` → `Ketchup::User.where`
- `User.dataset` → `Ketchup::User.dataset`

---

### Task 8: Run tests and verify

**Step 1: Run the full test suite**

Run: `rake test`
Expected: all tests pass

**Step 2: Run type checker**

Run: `rake check`
Expected: passes (rbs-inline + steep)

If `Ketchup::DB` causes Sequel issues, execute the DB escape hatch: unwrap `DB` from `module Ketchup` in db.rb, change `Ketchup::DB` back to `DB` in config.ru, Rakefile, and tests.

---

### Task 9: Commit

Run: jj commit (use jj-commit skill)

Message: "Move all classes and constants under the Ketchup module"
