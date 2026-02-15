# frozen_string_literal: true

Config = Data.define(:database_url, :sentry, :default_user) do
  SentryConfig = Data.define(:dsn, :env)

  def self.from_env(env = ENV)
    sentry_dsn = env["SENTRY_DSN"]
    new(
      database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" },
      sentry: sentry_dsn ? SentryConfig.new(dsn: sentry_dsn, env: env["SENTRY_ENV"]) : nil,
      default_user: env["DEFAULT_USER"]
    )
  end
end
