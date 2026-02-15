# frozen_string_literal: true

require "fileutils"

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

  def self.cache_dir
    base = ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache"))
    File.join(base, "ketchup", "snapshots")
  end

  def self.capture(output_dir:, port:)
    require "ferrum"

    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)

    user = User.find_or_create(login: "snapshot@example.com") { |u| u.name = "Snapshot User" }
    Seed.call(user: user, series: SEED_DATA)

    snapshots = build_snapshot_list(user, port)

    browser = Ferrum::Browser.new(
      headless: true,
      window_size: [1280, 900]
    )
    browser.headers.set(
      "Tailscale-User-Login" => user.login,
      "Tailscale-User-Name" => user.name
    )

    snapshots.each do |snap|
      browser.goto(snap[:url])
      # Allow JS/Alpine to initialize
      sleep 0.3

      path = File.join(output_dir, "#{snap[:name]}.png")

      if snap[:selector]
        browser.screenshot(path: path, selector: snap[:selector])
      else
        browser.screenshot(path: path)
      end
    end
  ensure
    browser&.quit
  end

  def self.build_snapshot_list(user, port)
    base = "http://127.0.0.1:#{port}"

    # Find the first series with history (for detail view)
    detail_series = user.series.find { |s| !s.completed_tasks.empty? }
    detail_series ||= user.series.first

    [
      { name: "dashboard", url: base, selector: nil },
      { name: "overdue-column", url: base, selector: ".column:first-child" },
      { name: "upcoming-column", url: base, selector: ".column:nth-child(2)" },
      { name: "series-detail", url: "#{base}/series/#{detail_series.id}", selector: nil },
      { name: "series-sidebar", url: "#{base}/series/#{detail_series.id}", selector: ".column-aside" }
    ]
  end

  def self.generate_diff_html(baseline_dir:, current_dir:, output_path:)
    baseline_images = Dir.glob(File.join(baseline_dir, "*.png")).map { |f| File.basename(f, ".png") }.sort
    current_images = Dir.glob(File.join(current_dir, "*.png")).map { |f| File.basename(f, ".png") }.sort
    all_names = (baseline_images + current_images).uniq.sort

    rows = all_names.map do |name|
      has_baseline = baseline_images.include?(name)
      has_current = current_images.include?(name)

      label = if !has_baseline
                " <span class=\"label new\">new</span>"
              elsif !has_current
                " <span class=\"label removed\">removed</span>"
              else
                ""
              end

      baseline_cell = if has_baseline
                        baseline_rel = File.join("baseline", "#{name}.png")
                        "<img src=\"#{baseline_rel}\" alt=\"baseline #{name}\">"
                      else
                        "<div class=\"placeholder\">No baseline</div>"
                      end

      current_cell = if has_current
                       current_rel = File.join("current", "#{name}.png")
                       "<img src=\"#{current_rel}\" alt=\"current #{name}\">"
                     else
                       "<div class=\"placeholder\">Removed</div>"
                     end

      <<~ROW
        <div class="snapshot">
          <h2>#{name}#{label}</h2>
          <div class="pair">
            <div class="side">
              <h3>Baseline</h3>
              #{baseline_cell}
            </div>
            <div class="side">
              <h3>Current</h3>
              #{current_cell}
            </div>
          </div>
        </div>
      ROW
    end

    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Ketchup Snapshot Diff</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { background: #1a1a2e; color: #e0e0e0; font-family: system-ui, sans-serif; padding: 2rem; }
          h1 { margin-bottom: 2rem; color: #fff; }
          .snapshot { margin-bottom: 3rem; }
          .snapshot h2 { margin-bottom: 1rem; color: #ccc; }
          .label { font-size: 0.75rem; padding: 0.15rem 0.5rem; border-radius: 4px; vertical-align: middle; }
          .label.new { background: #2d6a4f; color: #b7e4c7; }
          .label.removed { background: #6a2d2d; color: #e4b7b7; }
          .pair { display: flex; gap: 1rem; }
          .side { flex: 1; min-width: 0; }
          .side h3 { margin-bottom: 0.5rem; color: #999; font-size: 0.875rem; text-transform: uppercase; }
          .side img { width: 100%; border: 1px solid #333; border-radius: 4px; }
          .placeholder { padding: 3rem; text-align: center; color: #666; border: 1px dashed #333; border-radius: 4px; }
        </style>
      </head>
      <body>
        <h1>Ketchup Snapshot Diff</h1>
        #{rows.join("\n")}
      </body>
      </html>
    HTML

    File.write(output_path, html)
  end

  def self.generate_gallery_html(images_dir:, output_path:)
    images = Dir.glob(File.join(images_dir, "*.png")).sort.map { |f| File.basename(f) }

    items = images.map do |filename|
      name = File.basename(filename, ".png")
      <<~ITEM
        <div class="snapshot">
          <h2>#{name}</h2>
          <img src="#{filename}" alt="#{name}">
        </div>
      ITEM
    end

    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Ketchup Snapshots</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { background: #1a1a2e; color: #e0e0e0; font-family: system-ui, sans-serif; padding: 2rem; }
          h1 { margin-bottom: 2rem; color: #fff; }
          .snapshot { margin-bottom: 3rem; }
          .snapshot h2 { margin-bottom: 1rem; color: #ccc; }
          .snapshot img { max-width: 100%; border: 1px solid #333; border-radius: 4px; }
        </style>
      </head>
      <body>
        <h1>Ketchup Snapshots</h1>
        #{items.join("\n")}
      </body>
      </html>
    HTML

    File.write(output_path, html)
  end
end
