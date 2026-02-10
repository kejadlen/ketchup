# frozen_string_literal: true

require "sequel"

DB = Sequel.sqlite(ENV.fetch("DATABASE_URL") { "db/ketchup.db" })
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path("../db/migrate", __dir__))
