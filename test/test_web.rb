# frozen_string_literal: true

ENV["DATABASE_URL"] = ":memory:"

require "minitest/autorun"
require "rack/test"

require_relative "../lib/ketchup/web"

class TestWeb < Minitest::Test
  include Rack::Test::Methods

  def app = Web.app

  # TODO Wrap tests in a transaction or something?
  def setup
    DB[:tasks].delete
    DB[:series].delete
  end

  def test_root_shows_new_series_form
    get "/", {}, tailscale_headers
    assert last_response.ok?
    assert_includes last_response.body, '<form method="post" action="/series">'
    assert_includes last_response.body, 'name="note"'
    assert_includes last_response.body, 'name="interval_count"'
    assert_includes last_response.body, 'name="interval_unit"'
    assert_includes last_response.body, 'name="first_due_date"'
  end

  def test_root_shows_empty_state
    get "/", {}, tailscale_headers
    assert_includes last_response.body, "Nothing overdue."
    assert_includes last_response.body, "Nothing upcoming."
  end

  def test_root_shows_active_tasks
    post "/series", {
      note: "Call Mom", interval_unit: "week", interval_count: "2",
      first_due_date: "2026-03-01"
    }, tailscale_headers

    get "/", {}, tailscale_headers
    assert_includes last_response.body, "Call Mom"
    assert_includes last_response.body, "Mar 1"
  end

  def test_root_only_shows_own_tasks
    post "/series", {
      note: "Alice task", interval_unit: "week", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers(login: "alice@example.com", name: "Alice")

    post "/series", {
      note: "Bob task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers(login: "bob@example.com", name: "Bob")

    get "/", {}, tailscale_headers(login: "alice@example.com", name: "Alice")
    assert_includes last_response.body, "Alice task"
    refute_includes last_response.body, "Bob task"
  end

  def test_root_shows_current_user
    get "/", {}, tailscale_headers(name: "Alice")
    assert_includes last_response.body, "Alice"
  end

  def test_root_creates_user_record
    get "/", {}, tailscale_headers(login: "bob@example.com", name: "Bob")
    user = DB[:users].first(login: "bob@example.com")
    assert_equal "Bob", user[:name]
  end

  def test_root_requires_tailscale_user
    get "/"
    assert_equal 403, last_response.status
  end

  def test_create_series
    post "/series", {
      note: "Call Mom", interval_unit: "week", interval_count: "2",
      first_due_date: "2026-03-01"
    }, tailscale_headers
    assert last_response.redirect?

    series = DB[:series].first
    assert_equal "Call Mom", series[:note]
    assert_equal "week", series[:interval_unit]
    assert_equal 2, series[:interval_count]
  end

  def test_create_series_creates_first_task
    post "/series", {
      note: "Call Mom", interval_unit: "week", interval_count: "2",
      first_due_date: "2026-03-01"
    }, tailscale_headers

    series = DB[:series].first
    task = DB[:tasks].first(series_id: series[:id])
    assert_equal Date.new(2026, 3, 1), task[:due_date]
    assert_nil task[:completed_at]
  end

  def test_create_series_belongs_to_current_user
    post "/series", {
      note: "Dentist", interval_unit: "quarter", interval_count: "1",
      first_due_date: "2026-06-01"
    }, tailscale_headers(login: "dave@example.com", name: "Dave")

    series = DB[:series].first
    user = DB[:users].first(login: "dave@example.com")
    assert_equal user[:id], series[:user_id]
  end

  def test_create_series_strips_whitespace
    post "/series", {
      note: "  Trim me  ", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers
    assert_equal "Trim me", DB[:series].first[:note]
  end

  def test_create_series_rejects_empty_note
    post "/series", {
      note: "  ", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
  end

  def test_create_series_rejects_invalid_interval_unit
    post "/series", {
      note: "Nope", interval_unit: "fortnight", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
  end

  def test_create_series_rejects_zero_interval_count
    post "/series", {
      note: "Nope", interval_unit: "day", interval_count: "0",
      first_due_date: "2026-03-01"
    }, tailscale_headers
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
  end

  def test_create_series_rejects_invalid_due_date
    post "/series", {
      note: "Nope", interval_unit: "day", interval_count: "1",
      first_due_date: "not-a-date"
    }, tailscale_headers
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
    assert_equal 0, DB[:tasks].count
  end

  def test_complete_task
    post "/series", {
      note: "Call Mom", interval_unit: "week", interval_count: "2",
      first_due_date: "2026-03-01"
    }, tailscale_headers

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers
    assert last_response.redirect?

    old_task = DB[:tasks].first(id: task[:id])
    refute_nil old_task[:completed_at]

    new_task = DB[:tasks].where(completed_at: nil).first
    assert_equal Date.today + 14, new_task[:due_date]
  end

  def test_complete_task_advances_by_months
    post "/series", {
      note: "Dentist", interval_unit: "month", interval_count: "3",
      first_due_date: "2026-01-31"
    }, tailscale_headers

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers

    new_task = DB[:tasks].where(completed_at: nil).first
    assert_equal Date.today >> 3, new_task[:due_date]
  end

  def test_complete_task_requires_own_task
    post "/series", {
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers(login: "alice@example.com", name: "Alice")

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers(login: "bob@example.com", name: "Bob")
    assert_equal 404, last_response.status
  end

  def test_complete_task_requires_tailscale_user
    post "/series", {
      note: "Call Mom", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete"
    assert_equal 403, last_response.status
  end

  def test_create_series_requires_tailscale_user
    post "/series", {
      note: "Nope", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }
    assert_equal 403, last_response.status
  end

  private

  def tailscale_headers(
    login: "alice@example.com",
    name: "Alice",
    profile_pic: "https://example.com/alice.jpg"
  )
    {
      "HTTP_TAILSCALE_USER_LOGIN" => login,
      "HTTP_TAILSCALE_USER_NAME" => name,
      "HTTP_TAILSCALE_USER_PROFILE_PIC" => profile_pic
    }
  end
end
