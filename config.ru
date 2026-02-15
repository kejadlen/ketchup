# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

unless ENV["COMMIT_SHA"]
  ENV["COMMIT_SHA"] = `jj log -r @ --no-graph -T 'commit_id.short(7)' 2>/dev/null`.strip
  ENV["CHANGE_ID"] = `jj log -r @ --no-graph -T 'change_id.short(8)' 2>/dev/null`.strip
  ENV["BUILD_DATE"] = Time.now.strftime("%Y-%m-%d")
end

require_relative "lib/ketchup/web"

$stderr.puts CONFIG

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
