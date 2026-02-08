# frozen_string_literal: true

require "roda"

class Web < Roda
  route do |r|
    r.root do
      "Hello, World!"
    end
  end
end
