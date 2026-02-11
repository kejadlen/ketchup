# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Home < Phlex::HTML
    def initialize(current_user:, overdue:, upcoming:, sort:)
      @current_user = current_user
      @overdue = overdue
      @upcoming = upcoming
      @sort = sort
    end

    def view_template
      render Layout.new(current_user: @current_user) do
        div(class: "home") do
          div(class: "column") do
            div(class: "column-header") do
              h2 { "Overdue" }
              nav(class: "sort-toggle") do
                if @sort == :urgency
                  a(href: "/?sort=date") { "Date" }
                  span(class: "sort-active") { "Urgency" }
                else
                  span(class: "sort-active") { "Date" }
                  a(href: "/?sort=urgency") { "Urgency" }
                end
              end
            end
            task_list(@overdue, empty: "Nothing overdue.")
          end

          div(class: "column") do
            h2 { "Upcoming" }
            task_list(@upcoming, empty: "Nothing upcoming.")
          end

          div(class: "column column-aside") do
            h2(class: "aside-heading") { "New Series" }
            form(method: "post", action: "/series") do
              div(class: "field") do
                label(for: "note") { "Note" }
                textarea(id: "note", name: "note", rows: 2, required: true)
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
      end
    end

    private

    def task_list(tasks, empty:)
      if tasks.empty?
        p(class: "empty") { empty }
      else
        ul(class: "task-list") do
          tasks.each do |task|
            li(class: "task-item") { task_card(task) }
          end
        end
      end
    end

    def task_card(task)
      name = task[:note].lines.first&.strip || task[:note]
      overdue = task[:due_date] < Date.today

      div(class: ["task-card", ("task-overdue" if overdue)]) do
        form(method: "post", action: "/tasks/#{task[:id]}/complete", class: "complete-form") do
          button(type: "submit", title: "Complete", **{ "aria-label": "Complete #{name}" }) { "✓" }
        end
        div(class: "task-body") do
          span(class: "task-name") { name }
          div(class: "task-meta") do
            span(class: "task-due") do
              plain "Due #{task[:due_date]}"
            end
            span(class: "task-meta-sep") { "\u00B7" }
            span(class: "task-interval") do
              count = task[:interval_count]
              unit = task[:interval_unit]
              plain "Every #{count} #{count == 1 ? unit : "#{unit}s"}"
            end
            if task.urgency > 0
              span(class: "task-meta-sep") { "\u00B7" }
              span(class: "task-urgency") { "#{format("%.1f", task.urgency)}x" }
            end
          end
        end
      end
    end
  end
end
