# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "ketchup-snapshots"
  spec.version = "0.1.0"
  spec.authors = ["Alpha Chen"]
  spec.summary = "Headless screenshot capture and diffing infrastructure"
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ferrum"
end
