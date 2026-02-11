# frozen_string_literal: true

Config = Data.define(:database_url) do
  def self.from_env(env = ENV)
    new(
      database_url: env.fetch("DATABASE_URL") { "db/ketchup.db" }
    )
  end
end
