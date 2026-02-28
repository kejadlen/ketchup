# frozen_string_literal: true

require "simplecov"
SimpleCov.start

ENV["DATABASE_URL"] = ":memory:"
ENV["AUTH_HEADER"] = "Remote-User"
