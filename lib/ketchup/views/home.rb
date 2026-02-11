# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Home < Phlex::HTML
    def initialize(current_user:, tasks:)
      @current_user = current_user
      @tasks = tasks
    end

    def view_template
      render Layout.new(current_user: @current_user) do
        div(class: "home") do
          div(class: "panel") do
            details(class: "new-series") do
              summary { "New Series" }

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

                div(class: "field") do
                  label(for: "first_due_date") { "First due date" }
                  input(
                    type: "date", id: "first_due_date", name: "first_due_date",
                    value: Date.today.to_s, required: true
                  )
                end

                button(type: "submit") { "Create" }
              end
            end
          end

          div(class: "panel flow") do
            h2 { "Tasks" }

            if @tasks.empty?
              p(class: "empty") { "No tasks yet." }
            else
              ul(class: "task-list") do
                @tasks.each do |task|
                  li(class: "task-item") do
                    task_card(task)
                  end
                end
              end
            end
          end
        end
      end
    end

    private

    def task_card(task)
      name = task[:note].lines.first&.strip || task[:note]
      overdue = task[:due_date] < Date.today

      div(class: ["task-card", ("task-overdue" if overdue)]) do
        div(class: "task-body") do
          span(class: "task-name") { name }
          div(class: "task-meta") do
            span(class: "task-due") do
              plain overdue ? "Overdue — due #{task[:due_date]}" : "Due #{task[:due_date]}"
            end
            span(class: "task-meta-sep") { "\u00B7" }
            span(class: "task-interval") do
              count = task[:interval_count]
              unit = task[:interval_unit]
              plain "Every #{count} #{count == 1 ? unit : "#{unit}s"}"
            end
          end
        end
        form(method: "post", action: "/tasks/#{task[:id]}/complete", class: "complete-form") do
          button(type: "submit", title: "Complete", **{ "aria-label": "Complete #{name}" }) { "✓" }
        end
      end
    end
  end
end
