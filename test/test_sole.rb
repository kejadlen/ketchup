# frozen_string_literal: true

ENV["DATABASE_URL"] = ":memory:"

require "minitest/autorun"

require_relative "../lib/web"

class TestSole < Minitest::Test
  def setup
    DB[:tasks].delete
    DB[:series].delete
    DB[:users].delete
  end

  def test_sole_returns_single_record
    User.create(login: "alice@example.com", name: "Alice")
    user = User.where(login: "alice@example.com").sole
    assert_equal "Alice", user.name
  end

  def test_sole_raises_on_no_records
    assert_raises(Sequel::NoMatchingRow) do
      User.where(login: "nobody@example.com").sole
    end
  end

  def test_sole_raises_on_multiple_records
    User.create(login: "alice@example.com", name: "Alice")
    User.create(login: "bob@example.com", name: "Bob")

    assert_raises(Sequel::Plugins::Sole::TooManyRows) do
      User.dataset.sole
    end
  end
end
