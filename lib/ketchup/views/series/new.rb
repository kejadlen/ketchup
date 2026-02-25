# frozen_string_literal: true

require "phlex"

require_relative "../layout"

module Views
  module Series
    class New < Phlex::HTML
      def initialize(current_user:, csrf:, flash: nil)
        @current_user = current_user
        @csrf = csrf
        @flash = flash
      end

      def view_template
        render Layout.new(current_user: @current_user, title: "New Series — Ketchup", active_view: :new, flash: @flash, csrf: @csrf) do
          div(class: "dashboard") do
            div(class: "main-column") do
              section(class: "section") do
                div(class: "section-header") do
                  h2(class: "section-title") do
                    span(class: "section-title-text") { "New series" }
                  end
                  button(
                    class: "section-edit-btn",
                    id: "create-series-btn",
                    disabled: true
                  ) { "Create" }
                end

                form(method: "post", action: "/series", id: "new-series-form", class: "new-series-form", novalidate: true) do
                  input(type: "hidden", name: "_csrf", value: @csrf.call("/series"))
                  div(class: "field") do
                    label(for: "series-note-editor") { "Note" }
                    div(id: "series-note-editor", class: "series-note series-note--editable")
                  end

                  div(class: "field") do
                    label(for: "interval_count") { "Repeat every" }
                    div(class: "interval") do
                      input(
                        type: "number", id: "interval_count", name: "interval_count",
                        min: 1, value: 1, required: true
                      )
                      select(id: "interval_unit", name: "interval_unit", required: true) do
                        Views::INTERVAL_OPTIONS.each { |val, label| option(value: val) { label } }
                      end
                    end
                  end

                  div(class: "field") do
                    label(for: "first_due_date") { "First due date" }
                    input(
                      type: "date", id: "first_due_date", name: "first_due_date",
                      value: Date.today.to_s, required: true
                    )
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
