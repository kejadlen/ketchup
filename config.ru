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

if CONFIG.default_user
  require_relative "lib/ketchup/dev_auth"
  use Ketchup::DevAuth, CONFIG.default_user
end

run Web.freeze.app
