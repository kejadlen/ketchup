# frozen_string_literal: true

Config = Data.define(:database_url, :sentry, :default_user) do
  SentryConfig = Data.define(:dsn, :env)
  DefaultUser = Data.define(:login, :name) do
    def self.parse(value)
      login, name = value.split(":", 2)
      new(login: login, name: name || login)
    end
  end

  def self.from_env(env = ENV)
    sentry_dsn = env["SENTRY_DSN"]
    default_user = env["DEFAULT_USER"]
    new(
      database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" },
      sentry: sentry_dsn ? SentryConfig.new(dsn: sentry_dsn, env: env["SENTRY_ENV"]) : nil,
      default_user: default_user ? DefaultUser.parse(default_user) : nil
    )
  end
end
