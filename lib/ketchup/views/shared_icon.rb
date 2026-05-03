# frozen_string_literal: true

require "phlex"

module Ketchup
  module Views
    class SharedIcon < Phlex::HTML
      def view_template
        span(class: "task-shared", role: "img", "aria-label": "Shared") { "👥" }
      end
    end
  end
end
