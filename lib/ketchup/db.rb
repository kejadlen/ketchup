require "pathname"
require "sequel"

require_relative "config"

module Ketchup
  DB = Sequel.sqlite(CONFIG.database_url)
  Sequel.extension :migration
  Sequel::Migrator.run(DB, (Pathname(__dir__) / "../../db/migrate").expand_path)
end
