# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "flashbulb"
  spec.version = "0.1.0"
  spec.authors = ["Alpha Chen"]
  spec.summary = "Headless screenshot capture and visual diffing for Rack apps"
  spec.files = Dir["lib/**/*.rb", "templates/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ferrum"
end
