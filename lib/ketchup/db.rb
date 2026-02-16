# frozen_string_literal: true

require "sequel"

require_relative "config"

DB = Sequel.sqlite(CONFIG.database_url)
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path("../../db/migrate", __dir__))
