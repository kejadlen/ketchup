# frozen_string_literal: true

ENV["DATABASE_URL"] = ":memory:"

require "minitest/autorun"
require "rack/test"

require_relative "../lib/web"

class TestWeb < Minitest::Test
  include Rack::Test::Methods

  def app = Web.app

  def test_root_shows_new_series_form
    get "/", {}, tailscale_headers
    assert last_response.ok?
    assert_includes last_response.body, '<form method="post" action="/series">'
    assert_includes last_response.body, 'name="name"'
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

  def test_root_updates_user_name
    get "/", {}, tailscale_headers(login: "carol@example.com", name: "Carol")
    get "/", {}, tailscale_headers(login: "carol@example.com", name: "Carol C.")
    user = DB[:users].first(login: "carol@example.com")
    assert_equal "Carol C.", user[:name]
  end

  def test_root_requires_tailscale_user
    get "/"
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
