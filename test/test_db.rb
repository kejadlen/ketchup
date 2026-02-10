# frozen_string_literal: true

ENV["DATABASE_URL"] = ":memory:"

require "minitest/autorun"

require_relative "../lib/db"

class TestDB < Minitest::Test
  def setup
    DB[:tasks].delete
    DB[:series].delete
    @now = Time.now
    DB[:users]
      .insert_conflict(target: :login, update: { name: "Test", updated_at: @now })
      .insert(login: "test@example.com", name: "Test", created_at: @now, updated_at: @now)
    @user_id = DB[:users].first(login: "test@example.com")[:id]
  end

  def test_only_one_active_task_per_series
    series_id = create_series

    assert_raises(Sequel::UniqueConstraintViolation) do
      DB[:tasks].insert(series_id: series_id, due_date: Date.new(2026, 3, 15), created_at: @now, updated_at: @now)
    end
  end

  def test_completed_task_allows_new_active_task
    series_id = create_series

    DB[:tasks].where(series_id: series_id).update(completed_at: @now)

    DB[:tasks].insert(series_id: series_id, due_date: Date.new(2026, 3, 15), created_at: @now, updated_at: @now)

    assert_equal 1, DB[:tasks].where(series_id: series_id, completed_at: nil).count
  end

  private

  def create_series
    series_id = DB[:series].insert(
      user_id: @user_id, note: "Call Mom",
      interval_unit: "week", interval_count: 2,
      created_at: @now, updated_at: @now
    )
    DB[:tasks].insert(series_id: series_id, due_date: Date.new(2026, 3, 1), created_at: @now, updated_at: @now)
    series_id
  end
end
