# frozen_string_literal: true

require "roda"

require_relative "views/series/new"

class Web < Roda
  plugin :static, ["/css", "/js"]

  route do |r|
    r.root do
      Views::Series::New.new.call
    end
  end
end
