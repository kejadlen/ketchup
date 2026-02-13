# frozen_string_literal: true

require_relative "db"

Sequel::Model.plugin :timestamps, update_on_create: true
Sequel::Model.plugin :sole

class User < Sequel::Model
  one_to_many :series

  def active_tasks
    Task.active.for_user(self)
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

  def complete!
    DB.transaction do
      update(completed_at: Time.now)

      today = Date.today
      next_date = case series.interval_unit
                  when "day"
                    today + series.interval_count
                  when "week"
                    today + (7 * series.interval_count)
                  when "month"
                    today >> series.interval_count
                  when "quarter"
                    today >> (3 * series.interval_count)
                  when "year"
                    today >> (12 * series.interval_count)
                  else
                    fail
                  end
      Task.create(series_id: series.id, due_date: next_date)
    end
  end

  dataset_module do
    def active
      where(completed_at: nil)
    end

    def for_user(user)
      join(:series, id: :series_id)
        .where(Sequel[:series][:user_id] => user.id)
        .select_all(:tasks)
        .select_append(
          Sequel[:series][:note],
          Sequel[:series][:interval_unit],
          Sequel[:series][:interval_count]
        )
    end

  end
end
