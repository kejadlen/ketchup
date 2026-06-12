# frozen_string_literal: true

require "puma"
require "puma/configuration"
require "rack/builder"

require "flashbulb"

require_relative "seed"
require_relative "web"

module Ketchup
  module Snapshots
    class Capture < Flashbulb::Capture
      private

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

        # ── Dashboard with shared series ──

        shared_series = Series.create_with_first_task(
          user: User.first(login: "snapshot@example.com"),
          note: "Team standup\n\n*Monday* at **10am**",
          interval_unit: "week",
          interval_count: 1,
          first_due_date: Date.today - 1,
          shared: true
        )

        Series.create_with_first_task(
          user: User.first(login: "snapshot@example.com"),
          note: "Family dinner",
          interval_unit: "week",
          interval_count: 2,
          first_due_date: Date.today + 2,
          shared: true
        )

        entries << snap("dashboard-shared") do
          goto @base
          wait_for(".dashboard")
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
