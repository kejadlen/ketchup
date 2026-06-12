# frozen_string_literal: true

require "puma"
require "puma/configuration"
require "rack/builder"

require "flashbulb"

require_relative "seed"
require_relative "web"

module Ketchup
  module Snapshots
    def self.capture(output_dir:)
      Flashbulb::Capture.new(output_dir: output_dir, server: method(:default_server)) do |c, width:, height:|
        entries = []

        # ── Dashboard ──

        entries << c.snap("dashboard") do
          c.goto c.base
          c.wait_for(".dashboard")
        end

        c.wait_for(".complete-btn").click
        c.wait_for(".flash-bar")
        entries << c.snap("dashboard-after-complete")

        # ── New series ──

        entries << c.snap("new-series", selector: ".main-column") do
          c.goto "#{c.base}/series/new"
          c.wait_for("form[action='/series']")
        end

        fill_new_series_form(c,
          note: "Call the vet\n\nAsk about *vaccination schedule*\n- Bring **shot records**\n- Check flea meds",
          interval_count: 2,
          interval_unit: "week"
        )
        entries << c.snap("new-series-filled", selector: ".main-column")

        # ── Series detail (newly created) ──

        # Submit via the Create button to exercise the JS click handler
        c.wait_for("#create-series-btn").click
        c.wait_for("#series-note-detail")
        entries << c.snap("series-created", selector: ".main-column")

        # Toggle editing mode
        c.wait_for(".section-edit-btn").click
        c.wait_for(".series-note--editable")
        entries << c.snap("series-editing", selector: ".main-column")

        # Cancel editing, show archive button, then click to reveal confirmation
        c.wait_for(".section-edit-btn--cancel").click
        entries << c.snap("series-archive-button", selector: ".main-column")

        # ── Series detail (with history) ──

        series_with_history = find_series_with_mixed_history
        entries << c.snap("series-history", selector: ".main-column") do
          c.goto "#{c.base}/series/#{series_with_history.id}"
          c.wait_for(".task-history")
        end

        # Click "add a note" on a completed task that has no note
        c.browser.evaluate(<<~JS)
          document.querySelector('.task-history-item:has(.task-history-note-editor[data-value=""]) .task-history-add-note').click()
        JS
        textarea = c.wait_for('.task-history-note-editor[data-value=""] textarea')
        note_text = "Checked *both* lines\n- Front needs **new filter**\n- Back is fine"
        textarea.evaluate("this.value = #{note_text.to_json}")
        textarea.evaluate('this.dispatchEvent(new Event("input", { bubbles: true }))')
        entries << c.snap("series-add-note", selector: ".main-column")

        # Edit an older completed date (not the most recent) — active due date should not change
        entries << c.snap("series-edit-old-date", selector: ".main-column") do
          c.goto "#{c.base}/series/#{series_with_history.id}"
          c.wait_for(".task-history")
          c.browser.execute('document.querySelectorAll(".task-history-date")[1].click()')
          c.wait_for(".task-history-date-input")
        end

        old_date = (Date.today - 30).strftime("%Y-%m-%d")
        set_date_and_save(c, ".task-history-date-input", old_date)
        entries << c.snap("series-old-date-saved", selector: ".main-column") do
          c.goto "#{c.base}/series/#{series_with_history.id}"
          c.wait_for(".task-history")
        end

        # Edit the most recent completed date — active due date should update
        entries << c.snap("series-edit-latest-date", selector: ".main-column") do
          c.wait_for(".task-history-date").click
          c.wait_for(".task-history-date-input")
        end

        latest_date = (Date.today - 14).strftime("%Y-%m-%d")
        set_date_and_save(c, ".task-history-date-input", latest_date)
        entries << c.snap("series-latest-date-saved", selector: ".main-column") do
          c.goto "#{c.base}/series/#{series_with_history.id}"
          c.wait_for(".task-history")
        end

        # ── Dashboard with shared series ──

        Series.create_with_first_task(
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

        entries << c.snap("dashboard-shared") do
          c.goto c.base
          c.wait_for(".dashboard")
        end

        # ── User settings ──

        user = User.first(login: "snapshot@example.com")
        entries << c.snap("user-settings", selector: ".main-column") do
          c.goto "#{c.base}/users/#{user.id}"
          c.wait_for(".detail-fields")
        end

        c.wait_for(".section-edit-btn").click
        c.wait_for('input[name="email"]')
        entries << c.snap("user-editing", selector: ".main-column")

        entries
      end
    end

    def self.default_server(browser)
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
      Seed.call(user: user, series: Seed::DATA)

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

    def self.fill_new_series_form(c, note:, interval_count: 1, interval_unit: "day")
      textarea = c.wait_for("#series-note-editor textarea")
      textarea.focus
      note.each_line(chomp: true).with_index do |line, i|
        c.browser.keyboard.type(:Enter) if i > 0
        c.browser.keyboard.type(line) unless line.empty?
      end

      count_input = c.browser.at_css("input#interval_count")
      count_input.focus
      count_input.evaluate("this.value = ''")
      count_input.type(interval_count.to_s)

      unit_select = c.browser.at_css("select#interval_unit")
      unit_select.select(interval_unit)
    end

    # Set a date input's value via Alpine's x-model (dispatches input
    # event so the reactive model updates) then blur to trigger save().
    # Waits for the page to reload before returning.
    def self.set_date_and_save(c, selector, date)
      c.browser.execute("document.body.dataset.snapshotMarker = '1'")
      c.browser.execute(<<~JS)
        var input = document.querySelector('#{selector}');
        var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
        nativeInputValueSetter.call(input, '#{date}');
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        input.dispatchEvent(new Event('blur', { bubbles: true }));
      JS
      c.wait_for_reload
    end

    # Find a series that has both noted and un-noted completed tasks,
    # so the history screenshot shows both states.
    def self.find_series_with_mixed_history
      noted_ids = Task.exclude(completed_at: nil).where(Sequel.like(:note, "%*%")).select(:series_id)
      unnoted_ids = Task.exclude(completed_at: nil).where(note: nil).select(:series_id)
      Series.first(Sequel.&({ id: noted_ids }, { id: unnoted_ids })) || Series.first
    end
  end
end
