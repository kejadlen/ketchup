# frozen_string_literal: true

require "fileutils"

module Ketchup
  module Snapshots
    def self.cache_dir
      base = ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache"))
      File.join(base, "ketchup", "snapshots")
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

    class Capture
      def initialize(output_dir:, port:)
        require "ferrum"

        @output_dir = output_dir
        @port = port
        @base = "http://127.0.0.1:#{port}"
      end

      def call
        FileUtils.rm_rf(@output_dir)
        FileUtils.mkdir_p(@output_dir)

        user = User.find_or_create(login: "snapshot@example.com") { |u| u.name = "Snapshot User" }

        @browser = Ferrum::Browser.new(
          headless: true,
          window_size: [1280, 900]
        )
        @browser.headers.set(
          "Tailscale-User-Login" => user.login,
          "Tailscale-User-Name" => user.name
        )

        # Empty dashboard
        snap("empty-dashboard") do
          goto @base
        end

        # Create a series through the UI
        goto @base
        fill_new_series(note: "Call Mom", interval_count: 2, interval_unit: "week")
        @browser.at_css("#create-series-btn").click
        sleep 0.3

        # Series detail after creation (redirects to detail page)
        snap("series-detail")

        # Create more series for a populated dashboard
        [
          { note: "Water the plants", interval_count: 3, interval_unit: "day" },
          { note: "Clean the kitchen", interval_count: 1, interval_unit: "week" },
          { note: "Review finances", interval_count: 1, interval_unit: "month" },
          { note: "Dentist appointment", interval_count: 1, interval_unit: "quarter" },
        ].each do |series|
          goto @base
          fill_new_series(**series)
          @browser.at_css("#create-series-btn").click
          sleep 0.3
        end

        snap("dashboard") do
          goto @base
        end

        # Complete a task
        goto @base
        @browser.at_css(".complete-btn").click
        sleep 0.3

        snap("after-complete")
      ensure
        @browser&.quit
      end

      private

      def goto(url)
        @browser.goto(url)
        sleep 0.3
      end

      def snap(name, selector: nil)
        yield if block_given?
        sleep 0.3

        path = File.join(@output_dir, "#{name}.png")
        if selector
          @browser.screenshot(path: path, selector: selector)
        else
          @browser.screenshot(path: path)
        end
      end

      def fill_new_series(note:, interval_count: 1, interval_unit: "day")
        textarea = @browser.at_css("#series-note-editor textarea")
        textarea.focus
        textarea.type(note)

        count_input = @browser.at_css("input[name='interval_count']")
        count_input.focus
        count_input.evaluate("this.value = ''")
        count_input.type(interval_count.to_s)

        unit_select = @browser.at_css("select[name='interval_unit']")
        unit_select.select(interval_unit)
      end
    end
  end
end
