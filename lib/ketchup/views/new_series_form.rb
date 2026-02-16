# frozen_string_literal: true

require "phlex"

module Views
  class NewSeriesForm < Phlex::HTML
    def view_template
      div(class: "column column-aside column-aside--new") do
        div(class: "column-header") do
          h2 { "New Series" }
          button(type: "submit", form: "new-series-form", id: "create-series-btn", class: "aside-heading-action", disabled: true) { "Create" }
        end

        form(method: "post", action: "/series", id: "new-series-form", class: "task-detail") do
          div(id: "series-note-editor", class: "task-detail-note")

          dl(class: "task-detail-fields") do
            dt { "Repeat every" }
            dd(class: "detail-edit-interval") do
              input(
                type: "number", name: "interval_count",
                class: "detail-input detail-input-count",
                min: 1, value: 1, required: true
              )
              select(name: "interval_unit", class: "detail-input detail-input-unit", required: true) do
                INTERVAL_OPTIONS.each_with_index { |(val, label), i| option(value: val, selected: i == 0) { label } }
              end
            end

            dt { "First due date" }
            dd do
              input(
                type: "date", name: "first_due_date",
                class: "detail-input detail-input-date",
                value: Date.today.to_s, required: true
              )
            end
          end
        end
      end
    end
  end
end
