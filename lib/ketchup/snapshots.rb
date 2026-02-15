# frozen_string_literal: true

require "fileutils"
require "logger"

require "ferrum"
require "puma"
require "puma/configuration"

require_relative "web"

module Ketchup
  module Snapshots
    def self.cache_dir
      base = ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache"))
      File.join(base, "ketchup", "snapshots")
    end

    class Capture
      attr_reader :output_dir

      def initialize(logger: Logger.new($stderr))
        @output_dir = File.join(Snapshots.cache_dir, "current")
        @logger = logger
      end

      def call
        FileUtils.rm_rf(@output_dir)
        FileUtils.mkdir_p(@output_dir)

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

        port = launcher.connected_ports.first
        @base = "http://127.0.0.1:#{port}"
        @logger.info("Server listening on port #{port}")
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
          wait_for(".home")
        end

        # Create a series through the UI
        goto @base
        wait_for("#new-series-form")
        fill_new_series(note: "Call Mom", interval_count: 2, interval_unit: "week")
        @browser.at_css("#create-series-btn").click
        wait_for("#series-note-detail")

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
          wait_for("#new-series-form")
          fill_new_series(**series)
          @browser.at_css("#create-series-btn").click
          wait_for("#series-note-detail")
        end

        snap("dashboard") do
          goto @base
          wait_for(".home")
        end

        # Complete a task
        goto @base
        wait_for(".complete-btn").click
        wait_for(".task-history")

        snap("after-complete")
      ensure
        @browser&.quit
        if launcher
          $stdout.reopen(File::NULL)
          $stderr.reopen(File::NULL)
          launcher.stop
          thread&.join
          $stdout.reopen(saved_out)
          $stderr.reopen(saved_err)
        end
      end

      private

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

        path = File.join(@output_dir, "#{name}.png")
        if selector
          @browser.screenshot(path: path, selector: selector)
        else
          @browser.screenshot(path: path)
        end
        @logger.info(name)
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
