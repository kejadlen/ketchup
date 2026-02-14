# frozen_string_literal: true

require_relative "models"

module Seed
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
