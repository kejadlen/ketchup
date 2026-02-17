# frozen_string_literal: true

require "fileutils"
require "json"
require "logger"
require "uri"
require "pathname"

require "ferrum"
require "puma"
require "puma/configuration"
require "rack/builder"

require_relative "seed"
require_relative "web"

module Ketchup
  module Snapshots
    VIEWPORTS = {
      "desktop" => [1280, 900],
      "mobile" => [375, 812],
    }.freeze

    Entry = Data.define(:name, :path, :selector, :viewport) do
      def initialize(name:, path:, selector: nil, viewport: "desktop") = super

      def self.read_manifest(dir)
        manifest = dir / "manifest.json"
        return [] unless manifest.exist?

        JSON.parse(manifest.read).map do |e|
          new(name: e.fetch("name"), path: e.fetch("path"), selector: e["selector"], viewport: e.fetch("viewport", "desktop"))
        end
      end
    end

    Comparison = Data.define(:name, :baseline, :current)

    class Diff
      def initialize(baseline_dir:, current_dir:)
        @baseline_dir = Pathname(baseline_dir)
        @current_dir = Pathname(current_dir)
      end

      # Returns { "desktop" => [Comparison, ...], "mobile" => [Comparison, ...] }
      def comparisons_by_viewport
        VIEWPORTS.keys.each_with_object({}) do |viewport, result|
          baseline = read_entries(@baseline_dir / viewport)
          current = read_entries(@current_dir / viewport)
          result[viewport] = compare(baseline, current)
        end
      end

      # Flat list for backward compatibility (desktop only, or merged)
      def comparisons
        comparisons_by_viewport.values.first || []
      end

      private

      def read_entries(dir)
        Entry.read_manifest(dir).each_with_object({}) { |e, h| h[e.name] = e }
      end

      def compare(baseline, current)
        return current.map { |name, entry| Comparison.new(name: name, baseline: baseline[name], current: entry) } if baseline.keys == current.keys

        require "tempfile"
        baseline_file = Tempfile.new("baseline")
        current_file = Tempfile.new("current")
        baseline_file.write(baseline.keys.join("\n") + "\n")
        current_file.write(current.keys.join("\n") + "\n")
        baseline_file.close
        current_file.close

        `diff -u #{baseline_file.path} #{current_file.path}`.lines.drop(2).filter_map do |line|
          name = line[1..].chomp
          next if name.empty?
          case line[0]
          when " " then Comparison.new(name: name, baseline: baseline.fetch(name), current: current.fetch(name))
          when "-" then Comparison.new(name: name, baseline: baseline.fetch(name), current: nil)
          when "+" then Comparison.new(name: name, baseline: nil, current: current.fetch(name))
          end
        end
      end
    end

    class Capture
      def initialize(output_dir:, logger: Logger.new($stderr), &server)
        @output_dir = Pathname(output_dir)
        @logger = logger
        @server = server || method(:default_server)
      end

      def call
        FileUtils.rm_rf(@output_dir)
        @output_dir.mkpath

        @browser = Ferrum::Browser.new(
          headless: true,
          window_size: VIEWPORTS.fetch("desktop"),
          browser_options: { "force-device-scale-factor" => 2 }
        )

        @server.call(@browser) do |url|
          @base = url
          @logger.info("Server at #{@base}")

          VIEWPORTS.each do |viewport_name, (width, height)|
            @viewport = viewport_name
            @viewport_dir = @output_dir / viewport_name
            @viewport_dir.mkpath
            @browser.resize(width: width, height: height)
            @logger.info("Capturing #{viewport_name} (#{width}x#{height})")

            entries = run_capture(width: width, height: height)
            (@viewport_dir / "manifest.json").write(JSON.pretty_generate(entries.map(&:to_h)))
          end
        end
      ensure
        @browser&.quit
      end

      private

      # Snapshots, grouped by flow. Indentation means "then, without
      # navigating away." Each leaf is one screenshot.
      #
      # Dashboard
      #   full page
      #   complete a task, return to dashboard, full page
      #   overdue column only
      #   switch overdue sort to date, overdue column only
      #   upcoming column only
      #   toggle calendar view, upcoming column only
      #   scroll to bottom of calendar, upcoming column only
      #
      # New series
      #   empty sidebar form
      #   fill in note (markdown) and interval, sidebar
      #   submit, sidebar after redirect to series detail
      #   click Edit, sidebar with note in editing mode
      #
      # Existing series (one with noted + un-noted completed tasks)
      #   series detail with task history
      #   TODO: hover over un-noted task to reveal "add a note...", sidebar
      #   click "add a note", type markdown, sidebar
      #   focus an existing note's editor, sidebar
      def run_capture(width:, height:)
        entries = []

        # 1. Whole dashboard
        entries << snap("dashboard") do
          goto @base
          wait_for(".home")
        end

        # 2. Whole dashboard after completing a task
        wait_for(".complete-btn").click
        wait_for("#series-note-detail")
        goto @base
        wait_for(".home")
        entries << snap("dashboard-after-complete")

        # 3. Overdue column, sorted by urgency
        # Explicitly select Urgency — Alpine.$persist may carry "date"
        # from a previous viewport run.
        overdue_sel = '[x-data="sortable"]'
        wait_for("#{overdue_sel} .sort-toggle button:last-child").click
        entries << snap("overdue-urgency", selector: overdue_sel)

        # 4. Overdue column, sorted by date
        wait_for("#{overdue_sel} .sort-toggle button:first-child").click
        entries << snap("overdue-date", selector: overdue_sel)

        # Toggle back to urgency so the persist doesn't bleed into
        # the next viewport run.
        wait_for("#{overdue_sel} .sort-toggle button:last-child").click

        # 5. Upcoming column (list view)
        # Resize viewport to page height so headless Chrome renders
        # content below the fold (it won't paint outside the viewport).
        upcoming_sel = '[x-data="upcoming"]'
        with_rendered_page(width, height) do
          entries << snap("upcoming", selector: upcoming_sel)
        end

        # 6. Upcoming column, calendar view (top)
        # Toggle calendar on, then temporarily hide items past one
        # viewport-height so the selector capture stays compact.
        wait_for("#{upcoming_sel} .sort-toggle button").click
        wait_for(".calendar-day-empty")
        hide_upcoming_items_past(upcoming_sel, height)
        with_rendered_page(width, height) do
          entries << snap("upcoming-calendar", selector: upcoming_sel)
        end
        restore_hidden_items

        # 7. Upcoming column, calendar view (bottom)
        # Hide items before the horizon marker, keeping a few rows of
        # context above it so the screenshot shows the transition from
        # regular calendar into the far-future section.
        hide_upcoming_items_before_horizon(upcoming_sel, height)
        with_rendered_page(width, height) do
          entries << snap("upcoming-calendar-bottom", selector: upcoming_sel)
        end
        restore_hidden_items

        # Toggle calendar off — Alpine.$persist keeps showEmpty in
        # localStorage, which would bleed into the next viewport run.
        wait_for("#{upcoming_sel} .sort-toggle button").click

        # Steps 8-11: on desktop, these use the inline sidebar on the
        # dashboard. On mobile, series creation uses the standalone
        # /series/new page and the detail view stacks at the top.
        if element_visible?(".column-aside")
          # 8. Sidebar (new series)
          entries << snap("new-series", selector: ".column-aside")

          # 9. New series form filled in (with markdown), not created yet
          fill_new_series(
            note: "Call the vet\n\nAsk about *vaccination schedule*\n- Bring **shot records**\n- Check flea meds",
            interval_count: 2,
            interval_unit: "week"
          )
          entries << snap("new-series-editing", selector: ".column-aside")

          # 10. Series detail, post-creation
          wait_for("#create-series-btn").click
          wait_for("#series-note-detail")
          entries << snap("series-created", selector: ".column-aside")

          # 11. Series detail, editing note, post-creation
          wait_for("button.aside-heading-action").click
          entries << snap("series-editing", selector: ".column-aside")
        else
          # 8. Standalone new-series page
          entries << snap("new-series") do
            goto "#{@base}/series/new"
            wait_for("form[action='/series']")
          end

          # 9. New series form filled in
          fill_new_series_standalone(
            note: "Call the vet\n\nAsk about *vaccination schedule*\n- Bring **shot records**\n- Check flea meds",
            interval_count: 2,
            interval_unit: "week"
          )
          entries << snap("new-series-editing")

          # 10. Series detail, post-creation
          wait_for("button[type='submit']").click
          wait_for("#series-note-detail")
          entries << snap("series-created")

          # 11. Series detail, editing note, post-creation
          wait_for("button.aside-heading-action").click
          entries << snap("series-editing")
        end

        # 12. Series detail of a series with multiple finished tasks
        noted_ids = Task.exclude(completed_at: nil).where(Sequel.like(:note, "%*%")).select(:series_id)
        unnoted_ids = Task.exclude(completed_at: nil).where(note: nil).select(:series_id)
        series_with_history = Series.first(
          Sequel.&({ id: noted_ids }, { id: unnoted_ids })
        ) || Series.first
        entries << snap("series-detail") do
          goto "#{@base}/series/#{series_with_history.id}"
          wait_for(".task-history")
        end

        # TODO: hover snapshot — CSS :hover doesn't trigger in headless Chrome
        #   via mouse.move; need another approach to reveal ".task-history-add-note"

        # 13. Task: Add task note (with markdown)
        @browser.evaluate(<<~JS)
          document.querySelector('.task-history-item:has(.task-history-note-editor[data-value=""]) .task-history-add-note').click()
        JS
        textarea = wait_for('.task-history-note-editor[data-value=""] textarea')
        note_text = "Checked *both* lines\n- Front needs **new filter**\n- Back is fine"
        textarea.evaluate("this.value = #{note_text.to_json}")
        textarea.evaluate('this.dispatchEvent(new Event("input", { bubbles: true }))')
        entries << snap("task-add-note", selector: ".column-aside")

        # 14. Task: Edit task note (with markdown)
        existing = @browser.at_css('.task-history-note-editor:not([data-value=""]) textarea')
        existing.focus
        entries << snap("task-edit-note", selector: ".column-aside")

        entries
      end

      def default_server(browser)
        require_relative "dev_auth"

        app = Rack::Builder.app do
          use Ketchup::DevAuth, "snapshot@example.com"
          run Web.freeze.app
        end

        config = Puma::Configuration.new do |c|
          c.app app
          c.bind "tcp://127.0.0.1:0"
          c.log_requests false
          c.quiet
        end

        launcher = Puma::Launcher.new(config)
        saved_out, saved_err = $stdout.dup, $stderr.dup
        $stdout.reopen(File::NULL)
        $stderr.reopen(File::NULL)
        thread = Thread.new { launcher.run }
        sleep 0.1 until launcher.connected_ports.any?
        $stdout.reopen(saved_out)
        $stderr.reopen(saved_err)

        url = "http://127.0.0.1:#{launcher.connected_ports.first}"
        user = User.find_or_create(login: "snapshot@example.com") { |u| u.name = "Snapshot User" }
        Ketchup::Seed.call(user: user, series: Ketchup::Seed::DATA)

        yield url
      ensure
        if launcher
          $stdout.reopen(File::NULL)
          $stderr.reopen(File::NULL)
          launcher.stop
          thread&.join
          $stdout.reopen(saved_out)
          $stderr.reopen(saved_err)
        end
      end

      def goto(url)
        @browser.goto(url)
      end

      def wait_for(selector, timeout: 5)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        loop do
          node = @browser.at_css(selector)
          return node if node
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          raise Ferrum::TimeoutError, "waiting for #{selector}" if elapsed > timeout
          sleep 0.05
        end
      end

      def snap(name, selector: nil, area: nil)
        yield if block_given?

        file = @viewport_dir / "#{name}.png"
        if area
          @browser.screenshot(path: file.to_s, area: area)
        elsif selector && element_visible?(selector)
          @browser.execute("document.querySelector(#{selector.to_json}).style.padding = '1.5rem'")
          @browser.screenshot(path: file.to_s, selector: selector)
          @browser.execute("document.querySelector(#{selector.to_json}).style.padding = ''")
        else
          @browser.screenshot(path: file.to_s)
        end
        url_path = URI.parse(@browser.current_url).path
        @logger.info("#{@viewport}/#{name}")
        Entry.new(name: name, path: url_path, selector: selector, viewport: @viewport)
      end

      def element_visible?(selector)
        @browser.evaluate("(function() { var el = document.querySelector(#{selector.to_json}); if (!el) return null; var r = el.getBoundingClientRect(); return { width: r.width, height: r.height }; })()")
          &.then { |rect| rect["width"] > 0 && rect["height"] > 0 } || false
      end

      def fill_new_series(note:, interval_count: 1, interval_unit: "day")
        textarea = @browser.at_css("#series-note-editor textarea")
        textarea.focus
        textarea.evaluate("this.value = #{note.to_json}")
        textarea.evaluate('this.dispatchEvent(new Event("input", { bubbles: true }))')

        count_input = @browser.at_css("input[name='interval_count']")
        count_input.focus
        count_input.evaluate("this.value = ''")
        count_input.type(interval_count.to_s)

        unit_select = @browser.at_css("select[name='interval_unit']")
        unit_select.select(interval_unit)
      end

      def fill_new_series_standalone(note:, interval_count: 1, interval_unit: "day")
        textarea = @browser.at_css("textarea#note")
        textarea.focus
        textarea.evaluate("this.value = #{note.to_json}")
        textarea.evaluate('this.dispatchEvent(new Event("input", { bubbles: true }))')

        count_input = @browser.at_css("input#interval_count")
        count_input.focus
        count_input.evaluate("this.value = ''")
        count_input.type(interval_count.to_s)

        unit_select = @browser.at_css("select#interval_unit")
        unit_select.select(interval_unit)
      end

      # Hide calendar list items whose top edge exceeds +cutoff_px+ from
      # the column's top, so a selector capture stays compact.
      def hide_upcoming_items_past(selector, cutoff_px)
        @browser.evaluate(<<~JS)
          (function() {
            var col = document.querySelector(#{selector.to_json});
            var cutoff = col.getBoundingClientRect().top + #{cutoff_px};
            var items = col.querySelectorAll('.task-list > li');
            var toHide = [];
            items.forEach(function(li) {
              if (li.getBoundingClientRect().top > cutoff) toHide.push(li);
            });
            toHide.forEach(function(li) {
              li.dataset.snapshotHidden = '1';
              li.style.display = 'none';
            });
          })()
        JS
      end

      # Hide calendar list items above the "3 months" horizon marker,
      # keeping roughly 30 % of a viewport's worth of context above it.
      def hide_upcoming_items_before_horizon(selector, viewport_h)
        @browser.evaluate(<<~JS)
          (function() {
            var horizon = document.querySelector('.calendar-horizon');
            if (!horizon) return;
            var cutoff = horizon.getBoundingClientRect().top - #{(viewport_h * 0.3).to_i};
            var items = document.querySelector(#{selector.to_json}).querySelectorAll('.task-list > li');
            var toHide = [];
            items.forEach(function(li) {
              if (li.getBoundingClientRect().bottom < cutoff) toHide.push(li);
            });
            toHide.forEach(function(li) {
              li.dataset.snapshotHidden = '1';
              li.style.display = 'none';
            });
          })()
        JS
      end

      # Temporarily resize the viewport to the full page height so
      # headless Chrome paints everything, then restore after the block.
      def with_rendered_page(width, height)
        page_h = @browser.evaluate("document.body.scrollHeight")
        @browser.resize(width: width, height: page_h) if page_h > height
        yield
      ensure
        @browser.resize(width: width, height: height) if page_h > height
      end

      def restore_hidden_items
        @browser.evaluate(<<~JS)
          document.querySelectorAll('[data-snapshot-hidden]').forEach(function(el) {
            el.style.display = '';
            delete el.dataset.snapshotHidden;
          });
        JS
      end
    end
  end
end
