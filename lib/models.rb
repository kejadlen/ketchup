# frozen_string_literal: true

require_relative "db"

Sequel::Model.plugin :timestamps, update_on_create: true

class User < Sequel::Model
  one_to_many :series

  def self.upsert(login:, name:)
    user = find_or_create(login: login) { |u| u.name = name }
    user.update(name: name) if user.name != name
    user
  end
end

class Series < Sequel::Model
  many_to_one :user
  one_to_many :tasks

  INTERVAL_UNITS = %w[day week month quarter year].freeze

  def active_task
    tasks_dataset.where(completed_at: nil).first
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

    def by_due_date
      order(Sequel[:tasks][:due_date])
    end
  end
end
