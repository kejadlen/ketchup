# rbs_inline: enabled
# frozen_string_literal: true

Config = Data.define(
  :database_url, #: String
  :sentry, #: SentryConfig?
  :default_user, #: DefaultUser?
  :commit_sha, #: String?
  :change_id, #: String?
  :build_date, #: String?
)

class Config
  SentryConfig = Data.define(
    :dsn, #: String
    :env, #: String?
  )

  DefaultUser = Data.define(
    :login, #: String
    :name, #: String
  )

  # Reopened because rbs-inline ignores methods defined inside Data.define blocks.
  class DefaultUser
    #: (String) -> DefaultUser
    def self.parse(value)
      login, name = value.split(":", 2) #: [String, String?]
      new(login: login, name: name || login)
    end
  end

  #: () -> String
  def to_s
    parts = ["database=#{database_url}"]
    parts << "sentry=#{sentry.env || "on"}" if sentry
    parts << "default_user=#{default_user.login}" if default_user
    parts << "commit=#{commit_sha}" if commit_sha
    parts << "change=#{change_id}" if change_id
    parts << "built=#{build_date}" if build_date
    "Config(#{parts.join(", ")})"
  end

  #: (?Hash[String, String] env) -> Config
  def self.from_env(env = ENV)
    sentry_dsn = env["SENTRY_DSN"]
    default_user = env["DEFAULT_USER"]
    new(
      database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" },
      sentry: sentry_dsn ? SentryConfig.new(dsn: sentry_dsn, env: env["SENTRY_ENV"]) : nil,
      default_user: default_user ? DefaultUser.parse(default_user) : nil,
      commit_sha: env["COMMIT_SHA"],
      change_id: env["CHANGE_ID"]&.slice(0, 8),
      build_date: env["BUILD_DATE"]
    )
  end
end
