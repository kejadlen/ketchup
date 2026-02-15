# frozen_string_literal: true

require "fileutils"
require "json"
require "logger"
require "uri"
require "pathname"

require "ferrum"
require "puma"
require "puma/configuration"

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

      def run_capture
        entries = []

        # 1. Dashboard — populated overdue + upcoming columns
        entries << snap("dashboard") do
          goto @base
          wait_for(".home")
        end

        # 2. Series detail — pick one with completed history
        series_with_history = Series.first(
          id: Task.exclude(completed_at: nil).select(:series_id)
        ) || Series.first

        entries << snap("series-detail") do
          goto "#{@base}/series/#{series_with_history.id}"
          wait_for("#series-note-detail")
        end

        # 3. New series form with markdown, snap sidebar only
        goto @base
        wait_for("#new-series-form")
        fill_new_series(
          note: "Call the vet\n\nAsk about *vaccination schedule*\n- Bring **shot records**\n- Check flea meds",
          interval_count: 2,
          interval_unit: "week"
        )
        entries << snap("new-series-editing", selector: ".column-aside")

        # 4. Complete a task, snap the resulting detail page
        goto @base
        wait_for(".complete-btn").click
        wait_for(".task-history")
        entries << snap("after-complete")

        (@output_dir / "manifest.json").write(JSON.pretty_generate(entries.map(&:to_h)))
      end

      def default_server(browser)
        config = Puma::Configuration.new do |c|
          c.app Web.freeze.app
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

        browser.headers.set(
          "Tailscale-User-Login" => user.login,
          "Tailscale-User-Name" => user.name
        )

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

        file = @output_dir / "#{name}.png"
        if selector
          @browser.screenshot(path: file.to_s, selector: selector)
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
