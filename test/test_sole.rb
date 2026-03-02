# frozen_string_literal: true

require_relative "test_helper"

require "minitest/autorun"

require_relative "../lib/ketchup/web"

class TestSole < Minitest::Test
  def setup
    Ketchup::DB[:tasks].delete
    Ketchup::DB[:series].delete
    Ketchup::DB[:users].delete
  end

  def test_sole_returns_single_record
    Ketchup::User.create(login: "alice@example.com")
    user = Ketchup::User.where(login: "alice@example.com").sole
    assert_equal "alice@example.com", user.login
  end

  def test_sole_raises_on_no_records
    assert_raises(Sequel::NoMatchingRow) do
      Ketchup::User.where(login: "nobody@example.com").sole
    end
  end

  def test_sole_raises_on_multiple_records
    Ketchup::User.create(login: "alice@example.com")
    Ketchup::User.create(login: "bob@example.com")

    assert_raises(Sequel::Plugins::Sole::TooManyRows) do
      Ketchup::User.dataset.sole
    end
  end
end
