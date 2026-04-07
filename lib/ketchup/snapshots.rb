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

        `diff -U9999 #{baseline_file.path} #{current_file.path}`.lines.drop(2).filter_map do |line|
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

        browser_options = { "force-device-scale-factor" => 2 }
        browser_options["no-sandbox"] = nil if ENV["CI"]

        @browser = Ferrum::Browser.new(
          headless: true,
          window_size: VIEWPORTS.fetch("desktop"),
          browser_options: browser_options
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

      # Snapshots cover every page and its interactive states:
      #
      # Dashboard (/)
      #   default view with seed data
      #   after completing the focus task
      #
      # New series (/series/new)
      #   empty form
      #   form filled in
      #
      # Series detail (/series/:id)
      #   newly created series (no history)
      #   series in editing mode
      #   series with task history
      #   adding a note to a completed task
      #   editing an older completed date
      #   after saving the older completed date
      #   editing the most recent completed date
      #   after saving (active due date updates)
      #
      # User settings (/users/:id)
      #   viewing
      #   editing
      def run_capture(width:, height:)
        entries = []

        # ── Dashboard ──

        entries << snap("dashboard") do
          goto @base
          wait_for(".dashboard")
        end

        wait_for(".complete-btn").click
        wait_for(".flash-bar")
        entries << snap("dashboard-after-complete")

        # ── New series ──

        entries << snap("new-series", selector: ".main-column") do
          goto "#{@base}/series/new"
          wait_for("form[action='/series']")
        end

        fill_new_series_form(
          note: "Call the vet\n\nAsk about *vaccination schedule*\n- Bring **shot records**\n- Check flea meds",
          interval_count: 2,
          interval_unit: "week"
        )
        entries << snap("new-series-filled", selector: ".main-column")

        # ── Series detail (newly created) ──

        # Submit via the Create button to exercise the JS click handler
        wait_for("#create-series-btn").click
        wait_for("#series-note-detail")
        entries << snap("series-created", selector: ".main-column")

        # Toggle editing mode
        wait_for(".section-edit-btn").click
        wait_for(".series-note--editable")
        entries << snap("series-editing", selector: ".main-column")

        # Cancel editing, show archive button, then click to reveal confirmation
        wait_for(".section-edit-btn--cancel").click
        entries << snap("series-archive-button", selector: ".main-column")

        @browser.execute("document.querySelector('form[action$=\"/archive\"] button').click()")
        wait_for(".archive-confirm")
        entries << snap("series-archive-confirm", selector: ".main-column")

        # ── Series detail (with history) ──

        series_with_history = find_series_with_mixed_history
        entries << snap("series-history", selector: ".main-column") do
          goto "#{@base}/series/#{series_with_history.id}"
          wait_for(".task-history")
        end

        # Click "add a note" on a completed task that has no note
        @browser.evaluate(<<~JS)
          document.querySelector('.task-history-item:has(.task-history-note-editor[data-value=""]) .task-history-add-note').click()
        JS
        textarea = wait_for('.task-history-note-editor[data-value=""] textarea')
        note_text = "Checked *both* lines\n- Front needs **new filter**\n- Back is fine"
        textarea.evaluate("this.value = #{note_text.to_json}")
        textarea.evaluate('this.dispatchEvent(new Event("input", { bubbles: true }))')
        entries << snap("series-add-note", selector: ".main-column")

        # Edit an older completed date (not the most recent) — active due date should not change
        entries << snap("series-edit-old-date", selector: ".main-column") do
          goto "#{@base}/series/#{series_with_history.id}"
          wait_for(".task-history")
          @browser.execute('document.querySelectorAll(".task-history-date")[1].click()')
          wait_for(".task-history-date-input")
        end

        old_date = (Date.today - 30).strftime("%Y-%m-%d")
        set_date_and_save(".task-history-date-input", old_date)
        entries << snap("series-old-date-saved", selector: ".main-column") do
          goto "#{@base}/series/#{series_with_history.id}"
          wait_for(".task-history")
        end

        # Edit the most recent completed date — active due date should update
        entries << snap("series-edit-latest-date", selector: ".main-column") do
          wait_for(".task-history-date").click
          wait_for(".task-history-date-input")
        end

        latest_date = (Date.today - 14).strftime("%Y-%m-%d")
        set_date_and_save(".task-history-date-input", latest_date)
        entries << snap("series-latest-date-saved", selector: ".main-column") do
          goto "#{@base}/series/#{series_with_history.id}"
          wait_for(".task-history")
        end

        # ── User settings ──

        user = User.first(login: "snapshot@example.com")
        entries << snap("user-settings", selector: ".main-column") do
          goto "#{@base}/users/#{user.id}"
          wait_for(".detail-fields")
        end

        wait_for(".section-edit-btn").click
        wait_for('input[name="email"]')
        entries << snap("user-editing", selector: ".main-column")

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
        user = User.find_or_create(login: "snapshot@example.com")
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

      def snap(name, selector: nil)
        yield if block_given?

        file = @viewport_dir / "#{name}.png"
        if selector && element_visible?(selector)
          # Ferrum's selector screenshot captures the element's exact bounding
          # box, which sits flush against the edges. Temporary padding gives the
          # screenshot some breathing room so it doesn't look cropped.
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

      def fill_new_series_form(note:, interval_count: 1, interval_unit: "day")
        textarea = wait_for("#series-note-editor textarea")
        textarea.focus
        note.each_line(chomp: true).with_index do |line, i|
          @browser.keyboard.type(:Enter) if i > 0
          @browser.keyboard.type(line) unless line.empty?
        end

        count_input = @browser.at_css("input#interval_count")
        count_input.focus
        count_input.evaluate("this.value = ''")
        count_input.type(interval_count.to_s)

        unit_select = @browser.at_css("select#interval_unit")
        unit_select.select(interval_unit)
      end

      # Set a date input's value via Alpine's x-model (dispatches input
      # event so the reactive model updates) then blur to trigger save().
      # Waits for the page to reload before returning.
      def set_date_and_save(selector, date)
        @browser.execute("document.body.dataset.snapshotMarker = '1'")
        @browser.execute(<<~JS)
          var input = document.querySelector('#{selector}');
          var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
          nativeInputValueSetter.call(input, '#{date}');
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          input.dispatchEvent(new Event('blur', { bubbles: true }));
        JS
        wait_for_reload
      end

      def wait_for_reload(timeout: 5)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        loop do
          break unless @browser.evaluate("document.body.dataset.snapshotMarker")
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          raise Ferrum::TimeoutError, "waiting for page reload" if elapsed > timeout
          sleep 0.05
        end
      end

      # Find a series that has both noted and un-noted completed tasks,
      # so the history screenshot shows both states.
      def find_series_with_mixed_history
        noted_ids = Task.exclude(completed_at: nil).where(Sequel.like(:note, "%*%")).select(:series_id)
        unnoted_ids = Task.exclude(completed_at: nil).where(note: nil).select(:series_id)
        Series.first(Sequel.&({ id: noted_ids }, { id: unnoted_ids })) || Series.first
      end


    end
  end
end
