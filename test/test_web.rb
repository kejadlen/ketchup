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
    assert_includes last_response.body, "New Series"
    assert_includes last_response.body, 'action="/series"'
  end

  def test_root_shows_empty_state
    get "/", {}, tailscale_headers
    assert_includes last_response.body, "Nothing overdue."
    assert_includes last_response.body, "Nothing upcoming."
  end

  def test_root_shows_active_tasks
    create_series(note: "Call Mom", first_due_date: "2026-03-01", interval_unit: "week", interval_count: "2")

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
    assert_includes last_response["Location"], "/series/#{series[:id]}"
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
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers
    assert last_response.redirect?

    series = DB[:series].first
    assert_includes last_response["Location"], "/series/#{series[:id]}"

    old_task = DB[:tasks].first(id: task[:id])
    refute_nil old_task[:completed_at]

    new_task = DB[:tasks].where(completed_at: nil).first
    assert_equal Date.today + 14, new_task[:due_date]
  end

  def test_complete_task_advances_by_months
    create_series(note: "Dentist", interval_unit: "month", interval_count: "3",
                  first_due_date: "2026-01-31")

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
    create_series(note: "Call Mom", interval_unit: "day", interval_count: "1",
                  first_due_date: "2026-03-01")

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

  def test_task_card_links_to_series
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    get "/", {}, tailscale_headers
    assert_includes last_response.body, "href=\"/series/#{series[:id]}\""
    assert_includes last_response.body, "Call Mom"
  end

  def test_task_card_has_complete_form
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    get "/", {}, tailscale_headers
    assert_includes last_response.body, "action=\"/tasks/#{task[:id]}/complete\""
  end


  def test_series_sidebar_has_new_link
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, tailscale_headers
    assert_includes last_response.body, "+ New"
    assert_includes last_response.body, 'href="/"'
  end

  def test_get_series_shows_sidebar
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, tailscale_headers
    assert last_response.ok?
    assert_includes last_response.body, "Every 2 weeks"
    assert_includes last_response.body, "2026-03-01"
    assert_includes last_response.body, "task-selected"
  end

  def test_get_series_shows_completed_history
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers

    completed_task = DB[:tasks].first(id: task[:id])
    patch "/tasks/#{completed_task[:id]}/note", { note: "Left a message" }, tailscale_headers

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, tailscale_headers
    assert last_response.ok?
    assert_includes last_response.body, "Left a message"
    assert_includes last_response.body, "task-history"
  end

  def test_get_series_requires_own_series
    post "/series", {
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers(login: "alice@example.com", name: "Alice")

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, tailscale_headers(login: "bob@example.com", name: "Bob")
    assert_equal 404, last_response.status
  end

  def test_get_series_404_for_nonexistent
    get "/series/999999", {}, tailscale_headers
    assert_equal 404, last_response.status
  end

  def test_patch_note_saves_on_completed_task
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers

    completed_task = DB[:tasks].first(id: task[:id])
    patch "/tasks/#{completed_task[:id]}/note", { note: "Called, all good" }, tailscale_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal "Called, all good", body["note"]
    assert_equal "Called, all good", DB[:tasks].first(id: completed_task[:id])[:note]
  end

  def test_patch_note_rejects_active_task
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    patch "/tasks/#{task[:id]}/note", { note: "nope" }, tailscale_headers
    assert_equal 422, last_response.status
  end

  def test_patch_note_requires_own_task
    post "/series", {
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers(login: "alice@example.com", name: "Alice")

    task = DB[:tasks].first
    post "/tasks/#{task[:id]}/complete", {}, tailscale_headers(login: "alice@example.com", name: "Alice")

    completed_task = DB[:tasks].first(id: task[:id])
    patch "/tasks/#{completed_task[:id]}/note", { note: "hacked" }, tailscale_headers(login: "bob@example.com", name: "Bob")
    assert_equal 404, last_response.status
  end

  def test_patch_series_updates_note
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { note: "Call Dad" }, tailscale_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal "Call Dad", body["note"]
    assert_equal "Call Dad", DB[:series].first(id: series[:id])[:note]
  end

  def test_patch_series_updates_interval
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { interval_count: "3", interval_unit: "month" }, tailscale_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal 3, body["interval_count"]
    assert_equal "month", body["interval_unit"]

    updated = DB[:series].first(id: series[:id])
    assert_equal 3, updated[:interval_count]
    assert_equal "month", updated[:interval_unit]
  end

  def test_patch_series_updates_due_date
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    task = DB[:tasks].first(series_id: series[:id])
    patch "/series/#{series[:id]}", { due_date: "2026-04-15" }, tailscale_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal "2026-04-15", body["due_date"]
    assert_equal Date.new(2026, 4, 15), DB[:tasks].first(id: task[:id])[:due_date]
  end

  def test_patch_series_rejects_invalid_interval_unit
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { interval_unit: "fortnight" }, tailscale_headers
    assert_equal 422, last_response.status
  end

  def test_patch_series_rejects_zero_interval_count
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { interval_count: "0" }, tailscale_headers
    assert_equal 422, last_response.status
  end

  def test_patch_series_requires_own_series
    post "/series", {
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, tailscale_headers(login: "alice@example.com", name: "Alice")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { note: "hacked" }, tailscale_headers(login: "bob@example.com", name: "Bob")
    assert_equal 404, last_response.status
  end

  def test_patch_series_ignores_fields_not_provided
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { note: "Call Dad" }, tailscale_headers
    assert last_response.ok?

    updated = DB[:series].first(id: series[:id])
    assert_equal "Call Dad", updated[:note]
    assert_equal "week", updated[:interval_unit]
    assert_equal 2, updated[:interval_count]

    task = DB[:tasks].first(series_id: series[:id])
    assert_equal Date.new(2026, 3, 1), task[:due_date]
  end

  private

  def create_series(note:, interval_unit:, interval_count:, first_due_date:)
    post "/series", {
      note: note, interval_unit: interval_unit, interval_count: interval_count,
      first_due_date: first_due_date
    }, tailscale_headers
  end

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
