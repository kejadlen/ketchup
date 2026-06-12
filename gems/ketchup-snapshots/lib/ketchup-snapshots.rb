# frozen_string_literal: true

require "fileutils"
require "json"
require "logger"
require "uri"
require "pathname"

require "ferrum"

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

    # Raised when a snapshot page logs console errors/warnings or throws
    # uncaught JavaScript exceptions.
    class PageCheckError < StandardError
      def initialize(snap_name:, console_errors:, page_errors:)
        lines = ["Page errors during snap #{snap_name.inspect}:"]
        console_errors.each { |e| lines << "  console.#{e[:type]}: #{e[:text]}" }
        page_errors.each { |e| lines << "  page error: #{e}" }
        super(lines.join("\n"))
      end
    end

    class Capture
      def initialize(output_dir:, logger: Logger.new($stderr), &server)
        @output_dir = Pathname(output_dir)
        @logger = logger
        @server = server || method(:default_server)
        @console_messages = []
        @page_errors = []
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

        subscribe_page_errors

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

      def run_capture(width:, height:)
        raise NotImplementedError, "#{self.class}#run_capture"
      end

      def snap(name, selector: nil)
        check_page_errors(name) { yield if block_given? }

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

      def element_visible?(selector)
        @browser.evaluate("(function() { var el = document.querySelector(#{selector.to_json}); if (!el) return null; var r = el.getBoundingClientRect(); return { width: r.width, height: r.height }; })()")
          &.then { |rect| rect["width"] > 0 && rect["height"] > 0 } || false
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

      def subscribe_page_errors
        @browser.on("Runtime.consoleAPICalled") do |params|
          type = params["type"]
          text = params["args"].map { |a| a["value"].to_s }.join(" ")
          @console_messages << { type: type, text: text }
        end

        @browser.on("Runtime.exceptionThrown") do |params|
          detail = params.dig("exceptionDetails", "exception", "description")
          detail ||= params.dig("exceptionDetails", "text")
          @page_errors << detail.to_s
        end
      end

      def check_page_errors(snap_name)
        @console_messages.clear
        @page_errors.clear

        yield

        console_errors = @console_messages.select { |m| %(error warning).include?(m[:type]) }

        unless console_errors.empty? && @page_errors.empty?
          raise PageCheckError.new(
            snap_name:, console_errors:, page_errors: @page_errors.dup
          )
        end
      end
    end
  end
end
