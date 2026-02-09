# frozen_string_literal: true

require "minitest/autorun"
require "rack/test"

require_relative "../lib/web"

class TestWeb < Minitest::Test
  include Rack::Test::Methods

  def app = Web.app

  def test_root_shows_new_series_form
    get "/"

    assert last_response.ok?
    assert_includes last_response.body, '<form method="post" action="/series">'
    assert_includes last_response.body, 'name="name"'
  end
end
