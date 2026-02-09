# frozen_string_literal: true

require "phlex"

module Views
  module Series
    class New < Phlex::HTML
      def view_template
        h1 { "New Series" }

        form(method: "post", action: "/series") do
          label(for: "name") { "Name" }
          input(type: "text", id: "name", name: "name", required: true)

          button(type: "submit") { "Create" }
        end
      end
    end
  end
end
