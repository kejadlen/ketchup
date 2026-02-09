# frozen_string_literal: true

require "minitest/autorun"
require "rack/test"

require_relative "../lib/web"

class TestWeb < Minitest::Test
  include Rack::Test::Methods

  def app = Web.app

  def test_root_returns_hello_world
    get "/"

    assert last_response.ok?
    assert_equal "Hello, World!", last_response.body
  end
end
