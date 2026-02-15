# frozen_string_literal: true

require_relative "models"

module Ketchup
  module Seed
    DATA = [
      # Overdue — high urgency (short interval, many days past)
      {
        note: "Water the plants\n\nCheck soil moisture *before* watering",
        interval_unit: "day",
        interval_count: 3,
        due_date: Date.today - 6,
        history: [
          { due_date: Date.today - 9, completed_at: (Date.today - 9).to_time, note: "Done, no issues" },
          { due_date: Date.today - 12, completed_at: (Date.today - 11).to_time, note: nil },
        ]
      },
      # Overdue — moderate urgency
      {
        note: "Clean the kitchen",
        interval_unit: "week",
        interval_count: 1,
        due_date: Date.today - 4,
        history: []
      },
      # Overdue — low urgency (long interval, few days past)
      {
        note: "Review finances",
        interval_unit: "month",
        interval_count: 1,
        due_date: Date.today - 3,
        history: [
          { due_date: Date.today - 33, completed_at: (Date.today - 32).to_time, note: "All good\n\n- Checked statements\n- Updated budget" },
        ]
      },
      # Overdue — quarterly, just past due
      {
        note: "Dentist appointment\n\n**Dr. Chen**, 10am\n555-0142 to reschedule",
        interval_unit: "quarter",
        interval_count: 1,
        due_date: Date.today - 1,
        history: [
          { due_date: Date.today - 92, completed_at: (Date.today - 92).to_time, note: "Rescheduled from **last week**" },
          { due_date: Date.today - 183, completed_at: (Date.today - 182).to_time, note: nil },
        ]
      },
      # Upcoming — soon
      {
        note: "Call Mom\n\nAsk about *weekend plans*\n- Bring **birthday cake**\n- Check flight times",
        interval_unit: "week",
        interval_count: 2,
        due_date: Date.today + 2,
        history: [
          { due_date: Date.today - 12, completed_at: (Date.today - 12).to_time, note: "Had to call back *twice*" },
          { due_date: Date.today - 26, completed_at: (Date.today - 25).to_time, note: nil },
        ]
      },
      # Upcoming — next week
      {
        note: "Oil change",
        interval_unit: "month",
        interval_count: 3,
        due_date: Date.today + 8,
        history: []
      },
      # Upcoming — a couple weeks out
      {
        note: "Replace HVAC filter\n\nSize: **20x25x1**",
        interval_unit: "quarter",
        interval_count: 1,
        due_date: Date.today + 18,
        history: [
          { due_date: Date.today - 73, completed_at: (Date.today - 73).to_time, note: "All good\n\n- Changed filter\n- Reset thermostat" },
        ]
      },
      # Upcoming — far out
      {
        note: "Back up laptop\n\n- Time Machine to external drive\n- Sync cloud photos\n- Verify **offsite** backup",
        interval_unit: "month",
        interval_count: 1,
        due_date: Date.today + 24,
        history: [
          { due_date: Date.today - 6, completed_at: (Date.today - 6).to_time, note: "Took longer than expected — **2 hours** instead of 1" },
          { due_date: Date.today - 36, completed_at: (Date.today - 35).to_time, note: nil },
        ]
      },
      # Completed history only — daily
      {
        note: "Check smoke detectors",
        interval_unit: "year",
        interval_count: 1,
        due_date: Date.today + 140,
        history: [
          { due_date: Date.today - 225, completed_at: (Date.today - 225).to_time, note: "Replaced batteries in **hallway** unit" },
          { due_date: Date.today - 590, completed_at: (Date.today - 589).to_time, note: nil },
        ]
      },
      # Simple upcoming with no history
      {
        note: "Haircut",
        interval_unit: "month",
        interval_count: 2,
        due_date: Date.today + 45,
        history: []
      },
    ].freeze

    def self.call(user:, series:)
      series.each do |s|
        created = Series.create_with_first_task(
          user: user,
          note: s[:note],
          interval_unit: s[:interval_unit],
          interval_count: s[:interval_count],
          first_due_date: s[:due_date]
        )

        s[:history].each do |h|
          Task.create(
            series_id: created.id,
            due_date: h[:due_date],
            completed_at: h[:completed_at],
            note: h[:note]
          )
        end
      end
    end
  end
end
