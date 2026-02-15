# frozen_string_literal: true

require "fileutils"

module Ketchup
  module Snapshots
    def self.cache_dir
      base = ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache"))
      File.join(base, "ketchup", "snapshots")
    end

    class Capture
      def initialize(output_dir:)
        require "ferrum"
        require "puma"
        require "puma/configuration"

        @output_dir = output_dir
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
        thread = Thread.new { launcher.run }
        sleep 1 until launcher.connected_ports.any?

        @base = "http://127.0.0.1:#{launcher.connected_ports.first}"
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
        launcher&.stop
        thread&.join
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
