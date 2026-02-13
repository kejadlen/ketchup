# frozen_string_literal: true

require "sentry-ruby"

Sentry.init do |config|
  config.dsn = ENV.fetch("SENTRY_DSN")

  # Add data like request headers and IP for users,
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require_relative "lib/ketchup/web"

use Sentry::Rack::CaptureExceptions

run Web.freeze.app
