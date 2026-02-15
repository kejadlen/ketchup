# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require_relative "lib/ketchup/web"

if CONFIG.sentry
  require "sentry-ruby"

  Sentry.init do |config|
    config.dsn = CONFIG.sentry.dsn
    config.environment = CONFIG.sentry.env if CONFIG.sentry.env
    config.send_default_pii = true
  end

  use Sentry::Rack::CaptureExceptions
end

run Web.freeze.app
