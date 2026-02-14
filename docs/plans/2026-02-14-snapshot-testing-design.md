# Visual Snapshot Testing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Capture browser screenshots of key views, compare against baselines stored in GitHub release artifacts, and display differences in a local side-by-side viewer.

**Architecture:** A shared seed helper produces deterministic app state. Ferrum screenshots specific routes/elements and saves PNGs to `tmp/snapshots/`. Baselines come from GitHub release tarballs. A self-contained HTML viewer shows diffs locally. GitHub Pages hosts the current baseline gallery.

**Tech Stack:** Ruby, Ferrum (Chrome DevTools Protocol), Rack, Minitest (for seed helper tests), GitHub Actions, GitHub Pages

---

### Task 1: Extract shared seed helper

**Files:**
- Create: `lib/ketchup/seed.rb`
- Modify: `Rakefile:23-109`
- Test: `test/test_seed.rb`

**Step 1: Write the failing test**

Create `test/test_seed.rb` to verify the seed helper creates the expected records.

```ruby
# frozen_string_literal: true

ENV["DATABASE_URL"] = ":memory:"

require "minitest/autorun"
require_relative "../lib/ketchup/models"
require_relative "../lib/ketchup/seed"

class TestSeed < Minitest::Test
  def setup
    DB[:tasks].delete
    DB[:series].delete
    DB[:users].delete
  end

  def test_seed_creates_series_and_tasks
    user = User.create(login: "test@example.com", name: "Test")
    series_data = [
      {
        note: "Call Mom",
        interval_unit: "week",
        interval_count: 2,
        due_date: Date.new(2026, 3, 1),
        history: []
      }
    ]

    Seed.call(user: user, series: series_data)

    assert_equal 1, Series.count
    assert_equal 1, Task.count
    s = Series.first
    assert_equal "Call Mom", s.note
    assert_equal "week", s.interval_unit
    assert_equal 2, s.interval_count
    assert_equal Date.new(2026, 3, 1), Task.first.due_date
  end

  def test_seed_creates_completed_history
    user = User.create(login: "test@example.com", name: "Test")
    series_data = [
      {
        note: "Water plants",
        interval_unit: "day",
        interval_count: 3,
        due_date: Date.new(2026, 3, 1),
        history: [
          { due_date: Date.new(2026, 2, 26), completed_at: Time.new(2026, 2, 26, 10, 0, 0), note: "Done" },
          { due_date: Date.new(2026, 2, 23), completed_at: Time.new(2026, 2, 23, 10, 0, 0), note: nil }
        ]
      }
    ]

    Seed.call(user: user, series: series_data)

    assert_equal 3, Task.count
    assert_equal 2, Task.exclude(completed_at: nil).count
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/test_seed.rb`
Expected: FAIL — `Seed` not defined

**Step 3: Write minimal implementation**

Create `lib/ketchup/seed.rb`:

```ruby
# frozen_string_literal: true

require_relative "models"

module Seed
  def self.call(user:, series:)
    series.each do |s|
      created = Series.create_with_first_task(
        user: user,
        note: s[:note],
        interval_unit: s[:interval_unit],
        interval_count: s[:interval_count],
        first_due_date: s[:due_date]
      )

      s[:history].each do |h|
        Task.create(
          series_id: created.id,
          due_date: h[:due_date],
          completed_at: h[:completed_at],
          note: h[:note]
        )
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec ruby test/test_seed.rb`
Expected: PASS

**Step 5: Update `Rakefile` to use `Seed`**

Replace the body of the `seed` task in `Rakefile:23-109` with a call to `Seed.call`, building the randomized data inline:

```ruby
desc "Seed database with sample series and tasks"
task :seed do
  require "ketchup/seed"

  DB[:tasks].delete
  DB[:series].delete

  user = User.first || abort("No users yet — visit the app first to create one")

  notes = [
    "Call Mom",
    "Water the plants\n\nCheck soil moisture *before* watering",
    "Clean the kitchen",
    "Back up laptop\n\n- Time Machine to external drive\n- Sync cloud photos\n- Verify **offsite** backup",
    "Review finances",
    "Dentist appointment\n\n**Dr. Chen**, 10am\n555-0142 to reschedule",
    "Oil change",
    "Haircut",
    "Replace HVAC filter\n\nSize: **20x25x1**",
    "Check smoke detectors",
  ]

  max_count = {
    "day" => 14, "week" => 4, "month" => 6, "quarter" => 2, "year" => 2
  }
  overdue_spread = {
    "day" => 7, "week" => 21, "month" => 60, "quarter" => 120, "year" => 180
  }
  completion_notes = [
    "Done, no issues",
    "Rescheduled from **last week**",
    "Took longer than expected — **2 hours** instead of 1",
    "Had to call back *twice*",
    "All good\n\n- Changed filter\n- Reset thermostat",
  ]

  series_data = notes.map do |note|
    unit = max_count.keys.sample
    count = rand(1..max_count.fetch(unit))
    spread = overdue_spread.fetch(unit)
    due_date = Date.today + rand(-spread..spread)

    interval_days = case unit
                    when "day" then count
                    when "week" then 7 * count
                    when "month" then 30 * count
                    when "quarter" then 91 * count
                    when "year" then 365 * count
                    end

    history = if [true, false].sample
                rand(1..4).times.map do |i|
                  past_date = due_date - (interval_days * (i + 1))
                  {
                    due_date: past_date,
                    completed_at: past_date.to_time + rand(0..3) * 86400,
                    note: rand < 0.5 ? completion_notes.sample : nil
                  }
                end
              else
                []
              end

    {
      note: note,
      interval_unit: unit,
      interval_count: count,
      due_date: due_date,
      history: history
    }
  end

  Seed.call(user: user, series: series_data)
  puts "Seeded #{notes.length} series for #{user.name} (#{user.login})"
end
```

**Step 6: Run all tests**

Run: `bundle exec rake test`
Expected: PASS

**Step 7: Commit**

Message: "Extract shared seed helper from rake task"

---

### Task 2: Add ferrum gem and gitignore snapshots

**Files:**
- Modify: `Gemfile:15-22`
- Modify: `.gitignore`

**Step 1: Add ferrum to Gemfile**

Add `gem "ferrum"` to the development group in `Gemfile`:

```ruby
group :development do
  gem "ferrum"
  gem "minitest"
  gem "rack-test"
  gem "rake"
  gem "rbs-inline", require: false
  gem "ruby-lsp"
  gem "steep"
end
```

**Step 2: Bundle install**

Run: `bundle install`
Expected: ferrum and its dependencies install

**Step 3: Add tmp/snapshots to .gitignore**

Append to `.gitignore`:

```
tmp/
```

**Step 4: Commit**

Message: "Add ferrum gem and gitignore tmp/"

---

### Task 3: Create snapshot capture rake task

**Files:**
- Create: `lib/ketchup/snapshots.rb`
- Modify: `Rakefile` (add `snapshots:capture` task)

**Step 1: Create the Snapshots module**

Create `lib/ketchup/snapshots.rb` with the deterministic seed data, capture logic, and HTML viewer generation.

```ruby
# frozen_string_literal: true

require "fileutils"
require "ferrum"

module Snapshots
  SEED_DATA = [
    {
      note: "Call Mom",
      interval_unit: "week",
      interval_count: 2,
      due_date: Date.new(2026, 1, 15),
      history: [
        { due_date: Date.new(2026, 1, 1), completed_at: Time.new(2026, 1, 2, 10, 0, 0), note: "Left a message" },
        { due_date: Date.new(2025, 12, 18), completed_at: Time.new(2025, 12, 18, 14, 0, 0), note: nil }
      ]
    },
    {
      note: "Water the plants\n\nCheck soil moisture *before* watering",
      interval_unit: "day",
      interval_count: 3,
      due_date: Date.new(2026, 2, 10),
      history: []
    },
    {
      note: "Clean the kitchen",
      interval_unit: "week",
      interval_count: 1,
      due_date: Date.new(2026, 2, 20),
      history: [
        { due_date: Date.new(2026, 2, 13), completed_at: Time.new(2026, 2, 13, 9, 0, 0), note: "Deep cleaned the oven" }
      ]
    },
    {
      note: "Review finances",
      interval_unit: "month",
      interval_count: 1,
      due_date: Date.new(2026, 3, 1),
      history: []
    },
    {
      note: "Dentist appointment\n\n**Dr. Chen**, 10am\n555-0142 to reschedule",
      interval_unit: "quarter",
      interval_count: 1,
      due_date: Date.new(2026, 4, 15),
      history: []
    }
  ].freeze

  def self.capture(output_dir:, port:, tailscale_login: "alice@example.com", tailscale_name: "Alice")
    FileUtils.mkdir_p(output_dir)

    browser = Ferrum::Browser.new(headless: true)

    begin
      user = User.find_or_create(login: tailscale_login) { |u| u.name = tailscale_name }
      Seed.call(user: user, series: SEED_DATA)

      snapshots = build_snapshot_list(user, port)

      snapshots.each do |snap|
        browser.goto(snap[:url])
        browser.network.wait_for_idle

        if snap[:selector]
          node = browser.at_css(snap[:selector])
          node.screenshot(path: File.join(output_dir, "#{snap[:name]}.png"))
        else
          browser.screenshot(path: File.join(output_dir, "#{snap[:name]}.png"))
        end
      end
    ensure
      browser.quit
    end
  end

  def self.build_snapshot_list(user, port)
    base = "http://127.0.0.1:#{port}"
    first_series = user.series.first

    [
      { name: "dashboard-empty", url: base + "/", selector: nil },
      # We need a separate capture after seeding for the populated dashboard.
      # Since seeding already happened, dashboard-empty must be captured before seeding,
      # or we handle it differently. Let's just capture the populated state.
    ].tap do |list|
      # Populated dashboard (data already seeded)
      list.clear
      list << { name: "dashboard", url: base + "/", selector: nil }
      list << { name: "overdue-column", url: base + "/", selector: ".column:first-child" }
      list << { name: "upcoming-column", url: base + "/", selector: ".column:nth-child(2)" }

      if first_series
        list << { name: "series-detail", url: "#{base}/series/#{first_series.id}", selector: nil }
        list << { name: "series-sidebar", url: "#{base}/series/#{first_series.id}", selector: ".column-aside" }
      end
    end
  end

  def self.generate_diff_html(baseline_dir:, current_dir:, output_path:)
    baseline_images = Dir.glob("#{baseline_dir}/*.png").map { |f| File.basename(f, ".png") }.sort
    current_images = Dir.glob("#{current_dir}/*.png").map { |f| File.basename(f, ".png") }.sort
    all_names = (baseline_images + current_images).uniq.sort

    html = build_diff_page(all_names, baseline_dir, current_dir, baseline_images, current_images)
    File.write(output_path, html)
  end

  def self.generate_gallery_html(images_dir:, output_path:)
    names = Dir.glob("#{images_dir}/*.png").map { |f| File.basename(f, ".png") }.sort
    html = build_gallery_page(names, images_dir)
    File.write(output_path, html)
  end

  private_class_method def self.build_diff_page(names, baseline_dir, current_dir, baseline_names, current_names)
    rows = names.map do |name|
      has_baseline = baseline_names.include?(name)
      has_current = current_names.include?(name)

      label = if has_baseline && has_current
                nil
              elsif has_current
                "new"
              else
                "removed"
              end

      baseline_src = has_baseline ? "baseline/#{name}.png" : nil
      current_src = has_current ? "current/#{name}.png" : nil

      { name: name, label: label, baseline_src: baseline_src, current_src: current_src }
    end

    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Snapshot Diff</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { font-family: system-ui, sans-serif; padding: 2rem; background: #1a1a1a; color: #e0e0e0; }
          h1 { margin-bottom: 2rem; }
          .snapshot { margin-bottom: 3rem; border: 1px solid #333; border-radius: 8px; padding: 1.5rem; }
          .snapshot h2 { margin-bottom: 1rem; font-size: 1.1rem; }
          .snapshot .label { font-size: 0.8rem; padding: 2px 8px; border-radius: 4px; margin-left: 0.5rem; }
          .label-new { background: #2d5a2d; color: #90ee90; }
          .label-removed { background: #5a2d2d; color: #ee9090; }
          .diff { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
          .diff-side h3 { font-size: 0.9rem; color: #999; margin-bottom: 0.5rem; }
          .diff-side img { max-width: 100%; border: 1px solid #444; border-radius: 4px; }
          .diff-side .empty { color: #666; font-style: italic; padding: 2rem; text-align: center; border: 1px dashed #444; border-radius: 4px; }
        </style>
      </head>
      <body>
        <h1>Snapshot Diff</h1>
        #{rows.map { |r| diff_row_html(r) }.join("\n")}
      </body>
      </html>
    HTML
  end

  private_class_method def self.diff_row_html(row)
    label_html = row[:label] ? %(<span class="label label-#{row[:label]}">#{row[:label]}</span>) : ""
    baseline_html = row[:baseline_src] ? %(<img src="#{row[:baseline_src]}">) : %(<div class="empty">No baseline</div>)
    current_html = row[:current_src] ? %(<img src="#{row[:current_src]}">) : %(<div class="empty">Removed</div>)

    <<~HTML
      <div class="snapshot">
        <h2>#{row[:name]}#{label_html}</h2>
        <div class="diff">
          <div class="diff-side"><h3>Baseline</h3>#{baseline_html}</div>
          <div class="diff-side"><h3>Current</h3>#{current_html}</div>
        </div>
      </div>
    HTML
  end

  private_class_method def self.build_gallery_page(names, images_dir)
    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Ketchup Screenshots</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { font-family: system-ui, sans-serif; padding: 2rem; background: #1a1a1a; color: #e0e0e0; }
          h1 { margin-bottom: 2rem; }
          .snapshot { margin-bottom: 3rem; }
          .snapshot h2 { font-size: 1.1rem; margin-bottom: 0.5rem; }
          .snapshot img { max-width: 100%; border: 1px solid #444; border-radius: 4px; }
        </style>
      </head>
      <body>
        <h1>Ketchup Screenshots</h1>
        #{names.map { |n| %(<div class="snapshot"><h2>#{n}</h2><img src="#{n}.png"></div>) }.join("\n")}
      </body>
      </html>
    HTML
  end
end
```

**Step 2: Add snapshot rake tasks to Rakefile**

Add to the end of `Rakefile`:

```ruby
namespace :snapshots do
  desc "Capture screenshots of the app in key states"
  task :capture do
    ENV["DATABASE_URL"] = ":memory:"
    require "ketchup/seed"
    require "ketchup/snapshots"
    require "puma"
    require "puma/configuration"

    output_dir = File.expand_path("tmp/snapshots/current", __dir__)

    config = Puma::Configuration.new do |c|
      c.app Web.freeze.app
      c.bind "tcp://127.0.0.1:0"
      c.log_requests false
      c.quiet
    end

    launcher = Puma::Launcher.new(config)
    thread = Thread.new { launcher.run }
    sleep 0.5 until launcher.running

    port = launcher.connected_ports.first
    Snapshots.capture(output_dir: output_dir, port: port)
    launcher.stop
    thread.join

    puts "Screenshots saved to #{output_dir}"
  end

  desc "Compare current screenshots against baseline from latest release"
  task :diff do
    require "ketchup/snapshots"

    base_dir = File.expand_path("tmp/snapshots", __dir__)
    baseline_dir = File.join(base_dir, "baseline")
    current_dir = File.join(base_dir, "current")

    # Download baseline from latest release
    FileUtils.rm_rf(baseline_dir)
    FileUtils.mkdir_p(baseline_dir)

    tarball = File.join(base_dir, "baseline.tar.gz")
    system("gh", "release", "download", "--pattern", "snapshots.tar.gz", "--output", tarball, "--clobber", exception: false)

    if File.exist?(tarball)
      system("tar", "xzf", tarball, "-C", baseline_dir, exception: true)
      File.delete(tarball)
      puts "Downloaded baseline from latest release"
    else
      puts "No baseline found — showing current screenshots only"
    end

    Rake::Task["snapshots:capture"].invoke

    output_path = File.join(base_dir, "diff.html")
    Snapshots.generate_diff_html(
      baseline_dir: baseline_dir,
      current_dir: current_dir,
      output_path: output_path
    )
    puts "Diff viewer: #{output_path}"
  end

  desc "Capture, diff, and open the viewer"
  task :review do
    Rake::Task["snapshots:diff"].invoke
    system("open", File.expand_path("tmp/snapshots/diff.html", __dir__))
  end
end
```

**Step 3: Verify capture works**

Run: `bundle exec rake snapshots:capture`
Expected: PNGs appear in `tmp/snapshots/current/`

**Step 4: Verify diff works (no baseline yet)**

Run: `bundle exec rake snapshots:diff`
Expected: `tmp/snapshots/diff.html` created, all screenshots labeled "new"

**Step 5: Commit**

Message: "Add snapshot capture and diff rake tasks"

---

### Task 4: Add Tailscale header bypass for snapshot capture

The app requires Tailscale headers and returns 403 without them. The snapshot
capture uses a real browser against a real server, so it needs a way to inject
these headers. Add Rack middleware that sets fake Tailscale headers when an
environment variable is present.

**Files:**
- Modify: `lib/ketchup/web.rb`

**Step 1: Add middleware for fake auth**

Add a middleware class and conditionally insert it in `Web`:

```ruby
class Web < Roda
  if ENV["KETCHUP_FAKE_AUTH"]
    use(Class.new {
      def initialize(app)
        @app = app
      end

      def call(env)
        login, name = ENV["KETCHUP_FAKE_AUTH"].split(":", 2)
        env["HTTP_TAILSCALE_USER_LOGIN"] ||= login
        env["HTTP_TAILSCALE_USER_NAME"] ||= name
        @app.call(env)
      end
    })
  end
  # ... rest of Web
```

**Step 2: Update snapshot capture to set the env var**

In the capture rake task, before booting the server:

```ruby
ENV["KETCHUP_FAKE_AUTH"] = "alice@example.com:Alice"
```

**Step 3: Verify capture works end-to-end**

Run: `bundle exec rake snapshots:capture`
Expected: PNGs in `tmp/snapshots/current/` contain actual rendered pages (not 403 errors)

**Step 4: Commit**

Message: "Add fake auth middleware for snapshot capture"

---

### Task 5: CI — upload screenshots to release

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Add snapshot step to CI**

After the release creation step in the `build` job, add steps to capture and
upload screenshots. Chrome is pre-installed on `ubuntu-latest`.

```yaml
    - if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      run: |
        bundle exec rake snapshots:capture
        tar czf snapshots.tar.gz -C tmp/snapshots/current .
      env:
        DATABASE_URL: ":memory:"
        KETCHUP_FAKE_AUTH: "alice@example.com:Alice"
    - if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      env:
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      run: gh release upload "${{ steps.meta.outputs.version }}" snapshots.tar.gz
```

This requires `ruby/setup-ruby` in the build job as well since we need to run
the rake task. Add it after checkout, before the Docker steps.

**Step 2: Commit**

Message: "Upload screenshots to GitHub release in CI"

---

### Task 6: GitHub Pages gallery workflow

**Files:**
- Create: `.github/workflows/pages.yml`

**Step 1: Create the Pages workflow**

```yaml
name: Pages

on:
  release:
    types: [published]

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          mkdir -p gallery
          gh release download "${{ github.event.release.tag_name }}" --pattern "snapshots.tar.gz" --output snapshots.tar.gz
          tar xzf snapshots.tar.gz -C gallery
          bundle exec ruby -e "
            require_relative 'lib/ketchup/snapshots'
            Snapshots.generate_gallery_html(images_dir: 'gallery', output_path: 'gallery/index.html')
          "
      - uses: actions/upload-pages-artifact@v3
        with:
          path: gallery
      - id: deployment
        uses: actions/deploy-pages@v4
```

**Step 2: Commit**

Message: "Add GitHub Pages gallery workflow for screenshots"

---

### Task 7: Run full test suite and verify

**Step 1: Run all tests**

Run: `bundle exec rake test`
Expected: All tests pass, including the new seed tests.

**Step 2: Run snapshot capture locally**

Run: `bundle exec rake snapshots:review`
Expected: Browser opens with the diff viewer showing all screenshots as "new" (no baseline yet).

**Step 3: Final commit if any cleanup needed**
