# frozen_string_literal: true

ENV["DATABASE_URL"] = ":memory:"

require "minitest/autorun"
require "rack/test"

require_relative "../lib/ketchup/web"

class TestWeb < Minitest::Test
  include Rack::Test::Methods

  def app = Web.app

  def setup
    DB[:tasks].delete
    DB[:series].delete
    DB[:users].delete
  end

  def test_root_shows_new_series_form
    get "/", {}, auth_headers
    assert last_response.ok?
    assert_includes last_response.body, "New Series"
    assert_includes last_response.body, 'action="/series"'
  end

  def test_root_shows_empty_state
    get "/", {}, auth_headers
    assert_includes last_response.body, "Nothing overdue."
    assert_includes last_response.body, "Nothing upcoming."
  end

  def test_root_shows_active_tasks
    create_series(note: "Call Mom", first_due_date: "2026-03-01", interval_unit: "week", interval_count: "2")

    get "/", {}, auth_headers
    assert_includes last_response.body, "Call Mom"
    assert_includes last_response.body, "Mar 1"
  end

  def test_root_only_shows_own_tasks
    create_series(
      note: "Alice task", interval_unit: "week", interval_count: "1",
      first_due_date: "2026-03-01",
      headers: auth_headers(login: "alice@example.com")
    )

    create_series(
      note: "Bob task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01",
      headers: auth_headers(login: "bob@example.com")
    )

    get "/", {}, auth_headers(login: "alice@example.com")
    assert_includes last_response.body, "Alice task"
    refute_includes last_response.body, "Bob task"
  end

  def test_root_shows_current_user
    get "/", {}, auth_headers
    assert_includes last_response.body, "alice@example.com"
  end

  def test_root_creates_user_record
    get "/", {}, auth_headers(login: "bob@example.com")
    user = DB[:users].first(login: "bob@example.com")
    assert user
  end

  def test_root_requires_auth
    get "/"
    assert_equal 403, last_response.status
  end

  def test_create_series
    create_series(
      note: "Call Mom", interval_unit: "week", interval_count: "2",
      first_due_date: "2026-03-01"
    )
    assert last_response.redirect?

    series = DB[:series].first
    assert_equal "Call Mom", series[:note]
    assert_equal "week", series[:interval_unit]
    assert_equal 2, series[:interval_count]
    assert_includes last_response["Location"], "/series/#{series[:id]}"
  end

  def test_create_series_creates_first_task
    create_series(
      note: "Call Mom", interval_unit: "week", interval_count: "2",
      first_due_date: "2026-03-01"
    )

    series = DB[:series].first
    task = DB[:tasks].first(series_id: series[:id])
    assert_equal Date.new(2026, 3, 1), task[:due_date]
    assert_nil task[:completed_at]
  end

  def test_create_series_belongs_to_current_user
    create_series(
      note: "Dentist", interval_unit: "quarter", interval_count: "1",
      first_due_date: "2026-06-01",
      headers: auth_headers(login: "dave@example.com")
    )

    series = DB[:series].first
    user = DB[:users].first(login: "dave@example.com")
    assert_equal user[:id], series[:user_id]
  end

  def test_create_series_strips_whitespace
    create_series(
      note: "  Trim me  ", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    )
    assert_equal "Trim me", DB[:series].first[:note]
  end

  def test_create_series_rejects_empty_note
    create_series(
      note: "  ", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    )
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
  end

  def test_create_series_rejects_invalid_interval_unit
    create_series(
      note: "Nope", interval_unit: "fortnight", interval_count: "1",
      first_due_date: "2026-03-01"
    )
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
  end

  def test_create_series_rejects_zero_interval_count
    create_series(
      note: "Nope", interval_unit: "day", interval_count: "0",
      first_due_date: "2026-03-01"
    )
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
  end

  def test_create_series_rejects_invalid_due_date
    create_series(
      note: "Nope", interval_unit: "day", interval_count: "1",
      first_due_date: "not-a-date"
    )
    assert_equal 422, last_response.status
    assert_equal 0, DB[:series].count
    assert_equal 0, DB[:tasks].count
  end

  def test_complete_task
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    series = DB[:series].first
    complete_path = "/series/#{series[:id]}/tasks/#{task[:id]}/complete"
    csrf_post complete_path, {}, auth_headers
    assert last_response.redirect?

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
    series = DB[:series].first
    csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers

    new_task = DB[:tasks].where(completed_at: nil).first
    assert_equal Date.today >> 3, new_task[:due_date]
  end

  def test_complete_task_advances_from_given_date
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    task = Task.first
    task.complete!(today: Date.new(2026, 4, 1))

    new_task = Task.where(completed_at: nil).first
    assert_equal Date.new(2026, 4, 15), new_task.due_date
  end

  def test_complete_task_requires_own_task
    create_series(
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01",
      headers: auth_headers(login: "alice@example.com")
    )

    task = DB[:tasks].first
    csrf_post "/series/#{DB[:series].first[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers(login: "bob@example.com")
    assert_includes [403, 404], last_response.status
  end

  def test_complete_task_requires_auth
    create_series(note: "Call Mom", interval_unit: "day", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    post "/series/#{DB[:series].first[:id]}/tasks/#{task[:id]}/complete"
    assert_equal 403, last_response.status
  end

  def test_create_series_requires_auth
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
    get "/", {}, auth_headers
    assert_includes last_response.body, "href=\"/series/#{series[:id]}\""
    assert_includes last_response.body, "Call Mom"
  end

  def test_task_card_has_complete_form
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    get "/", {}, auth_headers
    series = DB[:series].first
    assert_includes last_response.body, "action=\"/series/#{series[:id]}/tasks/#{task[:id]}/complete\""
  end

  def test_task_card_has_csrf_token
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    get "/", {}, auth_headers
    assert_includes last_response.body, 'name="_csrf"'
  end

  def test_series_sidebar_has_new_link
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, auth_headers
    assert_includes last_response.body, "New"
    assert_includes last_response.body, 'href="/"'
  end

  def test_get_series_shows_sidebar
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, auth_headers
    assert last_response.ok?
    assert_includes last_response.body, "2 weeks"
    assert_includes last_response.body, "2026-03-01"
    assert_includes last_response.body, "task-selected"
  end

  def test_get_series_shows_completed_history
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    series = DB[:series].first
    csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers

    completed_task = DB[:tasks].first(id: task[:id])
    patch "/series/#{series[:id]}/tasks/#{completed_task[:id]}/note", { note: "Left a message" }, auth_headers
    get "/series/#{series[:id]}", {}, auth_headers
    assert last_response.ok?
    assert_includes last_response.body, "Left a message"
    assert_includes last_response.body, "task-history"
  end

  def test_get_series_requires_own_series
    create_series(
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01",
      headers: auth_headers(login: "alice@example.com")
    )

    series = DB[:series].first
    get "/series/#{series[:id]}", {}, auth_headers(login: "bob@example.com")
    assert_equal 404, last_response.status
  end

  def test_get_series_404_for_nonexistent
    get "/series/999999", {}, auth_headers
    assert_equal 404, last_response.status
  end

  def test_patch_note_saves_on_completed_task
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    series = DB[:series].first
    csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers

    completed_task = DB[:tasks].first(id: task[:id])
    patch "/series/#{series[:id]}/tasks/#{completed_task[:id]}/note", { note: "Called, all good" }, auth_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal "Called, all good", body["note"]
    assert_equal "Called, all good", DB[:tasks].first(id: completed_task[:id])[:note]
  end

  def test_patch_note_rejects_active_task
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "1",
                  first_due_date: "2026-03-01")

    task = DB[:tasks].first
    series = DB[:series].first
    patch "/series/#{series[:id]}/tasks/#{task[:id]}/note", { note: "nope" }, auth_headers
    assert_equal 422, last_response.status
  end

  def test_patch_note_requires_own_task
    create_series(
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01",
      headers: auth_headers(login: "alice@example.com")
    )

    task = DB[:tasks].first
    series = DB[:series].first
    csrf_post "/series/#{series[:id]}/tasks/#{task[:id]}/complete", {}, auth_headers(login: "alice@example.com")

    completed_task = DB[:tasks].first(id: task[:id])
    patch "/series/#{series[:id]}/tasks/#{completed_task[:id]}/note", { note: "hacked" }, auth_headers(login: "bob@example.com")
    assert_equal 404, last_response.status
  end

  def test_patch_series_updates_note
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { note: "Call Dad" }, auth_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal "Call Dad", body["note"]
    assert_equal "Call Dad", DB[:series].first(id: series[:id])[:note]
  end

  def test_patch_series_updates_interval
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { interval_count: "3", interval_unit: "month" }, auth_headers
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
    patch "/series/#{series[:id]}", { due_date: "2026-04-15" }, auth_headers
    assert last_response.ok?

    body = JSON.parse(last_response.body)
    assert_equal "2026-04-15", body["due_date"]
    assert_equal Date.new(2026, 4, 15), DB[:tasks].first(id: task[:id])[:due_date]
  end

  def test_patch_series_rejects_invalid_interval_unit
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { interval_unit: "fortnight" }, auth_headers
    assert_equal 422, last_response.status
  end

  def test_patch_series_rejects_zero_interval_count
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { interval_count: "0" }, auth_headers
    assert_equal 422, last_response.status
  end

  def test_patch_series_requires_own_series
    create_series(
      note: "Alice task", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01",
      headers: auth_headers(login: "alice@example.com")
    )

    series = DB[:series].first
    patch "/series/#{series[:id]}", { note: "hacked" }, auth_headers(login: "bob@example.com")
    assert_equal 404, last_response.status
  end

  def test_patch_series_ignores_fields_not_provided
    create_series(note: "Call Mom", interval_unit: "week", interval_count: "2",
                  first_due_date: "2026-03-01")

    series = DB[:series].first
    patch "/series/#{series[:id]}", { note: "Call Dad" }, auth_headers
    assert last_response.ok?

    updated = DB[:series].first(id: series[:id])
    assert_equal "Call Dad", updated[:note]
    assert_equal "week", updated[:interval_unit]
    assert_equal 2, updated[:interval_count]

    task = DB[:tasks].first(series_id: series[:id])
    assert_equal Date.new(2026, 3, 1), task[:due_date]
  end

  def test_get_user_shows_email_form
    get "/", {}, auth_headers  # create user
    user_id = DB[:users].first(login: "alice@example.com")[:id]

    get "/users/#{user_id}", {}, auth_headers
    assert last_response.ok?
    assert_includes last_response.body, "alice@example.com"
    assert_includes last_response.body, 'name="email"'
  end

  def test_post_user_email
    get "/", {}, auth_headers  # create user
    user_id = DB[:users].first(login: "alice@example.com")[:id]

    get "/users/#{user_id}", {}, auth_headers
    token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
    post "/users/#{user_id}/email", { "_csrf" => token, email: "alice@example.org" }, auth_headers
    assert last_response.redirect?

    user = DB[:users].first(id: user_id)
    assert_equal "alice@example.org", user[:email]
  end

  def test_post_user_email_clears_empty
    get "/", {}, auth_headers
    user_id = DB[:users].first(login: "alice@example.com")[:id]

    get "/users/#{user_id}", {}, auth_headers
    token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
    post "/users/#{user_id}/email", { "_csrf" => token, email: "" }, auth_headers

    user = DB[:users].first(id: user_id)
    assert_nil user[:email]
  end

  def test_get_user_rejects_other_user
    get "/", {}, auth_headers  # create alice
    get "/", {}, auth_headers(login: "bob@example.com")  # create bob
    bob_id = DB[:users].first(login: "bob@example.com")[:id]

    get "/users/#{bob_id}", {}, auth_headers
    assert_equal 404, last_response.status
  end

  def test_csrf_rejects_post_without_token
    get "/", {}, auth_headers  # establish session
    post "/series", {
      note: "No token", interval_unit: "day", interval_count: "1",
      first_due_date: "2026-03-01"
    }, auth_headers
    assert_equal 403, last_response.status
  end

  private

  def csrf_post(path, params = {}, headers = auth_headers)
    get "/", {}, headers  # establish session
    token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
    post path, params.merge("_csrf" => token), headers
  end

  def create_series(note:, interval_unit:, interval_count:, first_due_date:, headers: auth_headers)
    get "/", {}, headers  # establish session and get tokens
    token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
    post "/series", {
      _csrf: token,
      note: note, interval_unit: interval_unit, interval_count: interval_count,
      first_due_date: first_due_date
    }, headers
  end

  def auth_headers(login: "alice@example.com")
    { "HTTP_REMOTE_USER" => login }
  end
end
