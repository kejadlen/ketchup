# frozen_string_literal: true

require_relative "db"

module Ketchup
  Sequel::Model.plugin :timestamps, update_on_create: true
  Sequel::Model.plugin :sole
  Sequel::Model.plugin :many_through_many

  class User < Sequel::Model
    one_to_many :series
    many_through_many :tasks, [[:series, :user_id, :id]], right_primary_key: :series_id

    def active_tasks
      tasks_dataset
        .where(completed_at: nil)
        .where(Sequel[:series][:archived_at] => nil)
        .select_all(:tasks)
        .select_append(
          Sequel[:series][:note],
          Sequel[:series][:interval_unit],
          Sequel[:series][:interval_count]
        )
    end

    def overdue_tasks
      active_tasks.where { due_date < Date.today }
    end

    def upcoming_tasks
      active_tasks.where { due_date >= Date.today }.order(:due_date)
    end
  end

  class Series < Sequel::Model
    many_to_one :user
    one_to_many :tasks

    INTERVAL_UNITS = %w[day week month quarter year].freeze

    def active_task
      tasks_dataset.where(completed_at: nil).first
    end

    def completed_tasks
      tasks_dataset
        .exclude(completed_at: nil)
        .order(Sequel.desc(:completed_at))
        .select(:id, :due_date, :completed_at, :note)
        .all
    end

    def completion_stats
      completed = completed_tasks
      return { streak: 0, on_time_pct: 100, total: 0 } if completed.empty?

      streak = 0
      on_time = 0
      completed.each_with_index do |t, i|
        on_time += 1 if t[:completed_at].to_date <= t[:due_date]
        streak += 1 if i == streak && t[:completed_at].to_date <= t[:due_date]
      end

      { streak: streak, on_time_pct: (on_time * 100.0 / completed.size).round, total: completed.size }
    end

    def next_due_date(completed_on)
      case interval_unit
      when "day"
        completed_on + interval_count
      when "week"
        completed_on + (7 * interval_count)
      when "month"
        completed_on >> interval_count
      when "quarter"
        completed_on >> (3 * interval_count)
      when "year"
        completed_on >> (12 * interval_count)
      else
        fail
      end
    end

    def self.create_with_first_task(user:, note:, interval_unit:, interval_count:, first_due_date:)
      DB.transaction do
        series = create(
          user_id: user.id,
          note: note,
          interval_unit: interval_unit,
          interval_count: interval_count
        )

        Task.create(
          series_id: series.id,
          due_date: first_due_date
        )

        series
      end
    end
  end

  class Task < Sequel::Model
    many_to_one :series

    # Fixed day approximations for urgency scoring. complete! uses calendar
    # month arithmetic (Date#>>) for advancement so "1 month" lands on the
    # same day-of-month. Urgency only needs a rough ratio, so fixed counts
    # are fine and avoid coupling to a specific start date.
    INTERVAL_DAYS = {
      "day" => 1, "week" => 7, "month" => 30, "quarter" => 91, "year" => 365
    }.freeze

    def urgency
      days_overdue = Date.today - self[:due_date]
      return 0 if days_overdue <= 0

      count = self[:interval_count] || series.interval_count
      unit = self[:interval_unit] || series.interval_unit
      interval = count * INTERVAL_DAYS.fetch(unit)
      days_overdue.to_f / interval
    end

    def complete!(completed_on:)
      DB.transaction do
        update(completed_at: Time.new(completed_on.year, completed_on.month, completed_on.day))
        Task.create(series_id: series.id, due_date: series.next_due_date(completed_on))
      end
    end

    def undo_complete!
      DB.transaction do
        next_task = series.active_task
        next_task.destroy if next_task
        update(completed_at: nil)
      end
    end
  end
end
