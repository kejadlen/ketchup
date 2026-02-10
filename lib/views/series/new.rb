# frozen_string_literal: true

require "phlex"

require_relative "../layout"

module Views
  module Series
    class New < Phlex::HTML
      def initialize(current_user:)
        @current_user = current_user
      end

      def view_template
        render Layout.new(current_user: @current_user, title: "New Series — Ketchup") do
          div(class: "wrapper flow") do
            h1 { "New Series" }

            form(method: "post", action: "/series") do
              div(class: "field") do
                label(for: "note") { "Note" }
                textarea(id: "note", name: "note", rows: 3, required: true)
              end

              div(class: "field") do
                label(for: "interval_count") { "Repeat every" }
                div(class: "interval") do
                  input(
                    type: "number", id: "interval_count", name: "interval_count",
                    min: 1, value: 1, required: true
                  )
                  select(id: "interval_unit", name: "interval_unit", required: true) do
                    option(value: "day") { "day(s)" }
                    option(value: "week") { "week(s)" }
                    option(value: "month") { "month(s)" }
                    option(value: "quarter") { "quarter(s)" }
                    option(value: "year") { "year(s)" }
                  end
                end
              end

              button(type: "submit") { "Create" }
            end
          end
        end
      end
    end
  end
end
