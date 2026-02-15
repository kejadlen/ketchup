# frozen_string_literal: true

Config = Data.define(:database_url, :sentry, :default_user, :commit_sha, :change_id, :build_date)

class Config
  SentryConfig = Data.define(:dsn, :env)
  DefaultUser = Data.define(:login, :name) do
    def self.parse(value)
      login, name = value.split(":", 2)
      new(login: login, name: name || login)
    end
  end

  def to_s
    parts = ["database=#{database_url}"]
    parts << "sentry=#{sentry.env || "on"}" if sentry
    parts << "default_user=#{default_user.login}" if default_user
    parts << "commit=#{commit_sha}" if commit_sha
    parts << "change=#{change_id}" if change_id
    parts << "built=#{build_date}" if build_date
    "Config(#{parts.join(", ")})"
  end

  def self.from_env(env = ENV)
    sentry_dsn = env["SENTRY_DSN"]
    default_user = env["DEFAULT_USER"]
    new(
      database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" },
      sentry: sentry_dsn ? SentryConfig.new(dsn: sentry_dsn, env: env["SENTRY_ENV"]) : nil,
      default_user: default_user ? DefaultUser.parse(default_user) : nil,
      commit_sha: env["COMMIT_SHA"],
      change_id: env["CHANGE_ID"],
      build_date: env["BUILD_DATE"]
    )
  end
end
