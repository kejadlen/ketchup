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
    Entry = Data.define(:name, :path, :selector) do
      def initialize(name:, path:, selector: nil) = super

      def self.read_manifest(dir)
        manifest = dir / "manifest.json"
        return [] unless manifest.exist?

        JSON.parse(manifest.read).map { |e| new(name: e.fetch("name"), path: e.fetch("path"), selector: e["selector"]) }
      end
    end

    Comparison = Data.define(:name, :baseline, :current)

    class Diff
      def initialize(baseline_dir:, current_dir:)
        @baseline = Entry.read_manifest(baseline_dir).each_with_object({}) { |e, h| h[e.name] = e }
        @current = Entry.read_manifest(current_dir).each_with_object({}) { |e, h| h[e.name] = e }
      end

      def comparisons
        return unchanged if @baseline.keys == @current.keys

        require "tempfile"
        baseline_file = Tempfile.new("baseline")
        current_file = Tempfile.new("current")
        baseline_file.write(@baseline.keys.join("\n") + "\n")
        current_file.write(@current.keys.join("\n") + "\n")
        baseline_file.close
        current_file.close

        `diff -u #{baseline_file.path} #{current_file.path}`.lines.drop(2).filter_map do |line|
          name = line[1..].chomp
          next if name.empty?
          case line[0]
          when " " then Comparison.new(name: name, baseline: @baseline.fetch(name), current: @current.fetch(name))
          when "-" then Comparison.new(name: name, baseline: @baseline.fetch(name), current: nil)
          when "+" then Comparison.new(name: name, baseline: nil, current: @current.fetch(name))
          end
        end
      end

      private

      def unchanged
        @current.map { |name, entry| Comparison.new(name: name, baseline: @baseline[name], current: entry) }
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
          window_size: [1280, 900]
        )

        @server.call(@browser) do |url|
          @base = url
          @logger.info("Server at #{@base}")
          run_capture
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
      def run_capture
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

        # 3. Overdue column
        entries << snap("overdue", selector: '[x-data="sortable"]')

        # 4. Overdue column, sorted by date
        wait_for('[x-data="sortable"] .sort-toggle button').click
        entries << snap("overdue-by-date", selector: '[x-data="sortable"]')

        # 5. Upcoming column
        entries << snap("upcoming", selector: '[x-data="upcoming"]')

        # 6. Upcoming column, calendar view (top visible in viewport)
        wait_for('[x-data="upcoming"] .sort-toggle button').click
        wait_for(".calendar-day-empty")
        col = @browser.evaluate('document.querySelector(\'[x-data="upcoming"]\').getBoundingClientRect().toJSON()')
        viewport_h = @browser.evaluate("window.innerHeight")
        entries << snap("upcoming-calendar", area: { x: col["x"], y: 0, width: col["width"], height: viewport_h })

        # 7. Upcoming column, calendar view (bottom)
        #
        # HACK: headless Chrome doesn't render content outside the viewport,
        # so scrollTo + screenshot produces a blank image. Resizing the
        # viewport to the full page height forces Chrome to paint everything,
        # then we clip to the bottom viewport-sized slice of the column.
        # There's probably a better way — captureBeyondViewport, full-page
        # screenshot with crop, etc. — but this works for now.
        page_h = @browser.evaluate("document.body.scrollHeight")
        @browser.resize(width: 1280, height: page_h)
        entries << snap("upcoming-calendar-bottom", area: { x: col["x"], y: page_h - viewport_h, width: col["width"], height: viewport_h })
        @browser.resize(width: 1280, height: 900)

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

        (@output_dir / "manifest.json").write(JSON.pretty_generate(entries.map(&:to_h)))
      end

      def default_server(browser)
        require_relative "dev_auth"

        app = Rack::Builder.app do
          default_user = Config::DefaultUser.new(login: "snapshot@example.com", name: "Snapshot User")
          use Ketchup::DevAuth, default_user
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

        file = @output_dir / "#{name}.png"
        if area
          @browser.screenshot(path: file.to_s, area: area)
        elsif selector
          @browser.execute("document.querySelector(#{selector.to_json}).style.padding = '1.5rem'")
          @browser.screenshot(path: file.to_s, selector: selector)
          @browser.execute("document.querySelector(#{selector.to_json}).style.padding = ''")
        else
          @browser.screenshot(path: file.to_s)
        end
        url_path = URI.parse(@browser.current_url).path
        @logger.info(name)
        Entry.new(name: name, path: url_path, selector: selector)
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
    end
  end
end
