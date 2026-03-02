# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

unless ENV["COMMIT_SHA"]
  ENV["COMMIT_SHA"] = `jj log -r @ --no-graph -T 'commit_id.short(7)' 2>/dev/null`.strip
  ENV["CHANGE_ID"] = `jj log -r @ --no-graph -T 'change_id.short(8)' 2>/dev/null`.strip
  ENV["BUILD_DATE"] = Time.now.strftime("%Y-%m-%d")
end

require_relative "lib/ketchup/config"

if Ketchup::CONFIG.otel
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/rack"

  OpenTelemetry::SDK.configure do |c|
    c.service_name = "ketchup"
    c.use "OpenTelemetry::Instrumentation::Rack"
  end

  use(*OpenTelemetry::Instrumentation::Rack::Instrumentation.instance.middleware_args)
end

$stderr.puts Ketchup::CONFIG

if Ketchup::CONFIG.sentry
  require "sentry-ruby"

  Sentry.init do |config|
    config.dsn = Ketchup::CONFIG.sentry.dsn
    config.environment = Ketchup::CONFIG.sentry.env if Ketchup::CONFIG.sentry.env
    config.send_default_pii = true
  end

  use Sentry::Rack::CaptureExceptions
end

if Ketchup::CONFIG.default_user
  require_relative "lib/ketchup/dev_auth"
  use Ketchup::DevAuth, Ketchup::CONFIG.default_user

  require_relative "lib/ketchup/seed"
  user = Ketchup::User.find_or_create(login: Ketchup::CONFIG.default_user)
  if user.series_dataset.empty?
    Ketchup::Seed.call(user: user, series: Ketchup::Seed::DATA)
    $stderr.puts "Seeded #{Ketchup::Seed::DATA.length} series for #{user.login}"
  end
end

require_relative "lib/ketchup/web"
run Ketchup::Web.freeze.app
