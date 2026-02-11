# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require_relative "lib/ketchup/web"

run Web.freeze.app
