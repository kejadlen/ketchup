# rbs_inline: enabled
# frozen_string_literal: true

require "securerandom"

Config = Data.define(
  :database_url,   #: String
  :session_secret, #: String
  :auth_header,    #: String
  :sentry,         #: SentryConfig?
  :default_user,   #: String?
  :commit_sha,     #: String?
  :change_id,      #: String?
  :build_date,     #: String?
)

class Config
  SentryConfig = Data.define(
    :dsn, #: String
    :env, #: String?
  )

  #: () -> String
  def to_s
    parts = ["database=#{database_url}"]
    parts << "auth=#{auth_header}"
    parts << "sentry=#{sentry.env || "on"}" if sentry
    parts << "default_user=#{default_user}" if default_user
    parts << "commit=#{commit_sha}" if commit_sha
    parts << "change=#{change_id}" if change_id
    parts << "built=#{build_date}" if build_date
    "Config(#{parts.join(", ")})"
  end

  #: (?Hash[String, String] env) -> Config
  def self.from_env(env = ENV)
    sentry_dsn = env["SENTRY_DSN"]
    new(
      database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" },
      session_secret: env.fetch("SESSION_SECRET") { SecureRandom.hex(64) },
      auth_header: env.fetch("AUTH_HEADER", "Remote-User"),
      sentry: sentry_dsn ? SentryConfig.new(dsn: sentry_dsn, env: env["SENTRY_ENV"]) : nil,
      default_user: env["DEFAULT_USER"],
      commit_sha: env["COMMIT_SHA"],
      change_id: env["CHANGE_ID"]&.slice(0, 8),
      build_date: env["BUILD_DATE"]
    )
  end
end

CONFIG = Config.from_env
