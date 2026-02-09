# frozen_string_literal: true

require "phlex"

require_relative "../layout"

module Views
  module Series
    class New < Phlex::HTML
      def view_template
        render Layout.new(title: "New Series — Ketchup") do
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
end
