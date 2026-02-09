# frozen_string_literal: true

require "roda"

class Web < Roda
  plugin :render, engine: "erb"

  route do |r|
    r.root do
      render("series/new")
    end
  end
end
