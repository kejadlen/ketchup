# frozen_string_literal: true

require_relative "test_helper"

require "minitest/autorun"
require_relative "../lib/ketchup/models"
require_relative "../lib/ketchup/seed"

class TestSeed < Minitest::Test
  def setup
    Ketchup::DB[:tasks].delete
    Ketchup::DB[:series].delete
    Ketchup::DB[:users].delete
  end

  def test_seed_creates_series_and_tasks
    user = Ketchup::User.create(login: "test@example.com")
    series_data = [
      {
        note: "Call Mom",
        interval_unit: "week",
        interval_count: 2,
        due_date: Date.new(2026, 3, 1),
        history: []
      }
    ]

    Ketchup::Seed.call(user: user, series: series_data)

    assert_equal 1, Ketchup::Series.count
    assert_equal 1, Ketchup::Task.count
    s = Ketchup::Series.first
    assert_equal "Call Mom", s.note
    assert_equal "week", s.interval_unit
    assert_equal 2, s.interval_count
    assert_equal Date.new(2026, 3, 1), Ketchup::Task.first.due_date
  end

  def test_seed_creates_completed_history
    user = Ketchup::User.create(login: "test@example.com")
    series_data = [
      {
        note: "Water plants",
        interval_unit: "day",
        interval_count: 3,
        due_date: Date.new(2026, 3, 1),
        history: [
          { due_date: Date.new(2026, 2, 26), completed_at: Time.new(2026, 2, 26, 10, 0, 0), note: "Done" },
          { due_date: Date.new(2026, 2, 23), completed_at: Time.new(2026, 2, 23, 10, 0, 0), note: nil }
        ]
      }
    ]

    Ketchup::Seed.call(user: user, series: series_data)

    assert_equal 3, Ketchup::Task.count
    assert_equal 2, Ketchup::Task.exclude(completed_at: nil).count
  end
end
