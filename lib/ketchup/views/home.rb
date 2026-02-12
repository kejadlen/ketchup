# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Home < Phlex::HTML
    def initialize(current_user:, overdue:, upcoming:)
      @current_user = current_user
      @overdue = overdue
      @upcoming = upcoming
    end

    def view_template
      render Layout.new(current_user: @current_user) do
        div(class: "home") do
          div(class: "column", "x-data": "sortable") do
            div(class: "column-header") do
              h2 { "Overdue" }
              nav(class: "sort-toggle") do
                button(
                  "x-on:click": "sort = 'date'",
                  "x-bind:class": "sort === 'date' && 'sort-active'",
                  "x-bind:disabled": "sort === 'date'"
                ) { "Date" }
                button(
                  "x-on:click": "sort = 'urgency'",
                  "x-bind:class": "sort === 'urgency' && 'sort-active'",
                  "x-bind:disabled": "sort === 'urgency'"
                ) { "Urgency" }
              end
            end
            task_list(@overdue, empty: "Nothing overdue.", sortable: true)
          end

          div(class: "column", "x-data": "upcoming") do
            div(class: "column-header") do
              h2 { "Upcoming" }
              nav(class: "sort-toggle") do
                button(
                  "x-on:click": "showEmpty = !showEmpty",
                  "x-bind:class": "showEmpty && 'sort-active'"
                ) { "Calendar" }
              end
            end
            upcoming_list(@upcoming)
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

    def task_list(tasks, empty:, sortable: false)
      if tasks.empty?
        p(class: "empty") { empty }
      else
        ul(class: "task-list") do
          tasks.each do |task|
            attrs = { class: "task-item" }
            if sortable
              attrs[:"data-urgency"] = format("%.4f", task.urgency)
              attrs[:"data-due-date"] = task[:due_date].to_s
            end
            li(**attrs) { task_card(task) }
          end
        end
      end
    end

    def upcoming_list(tasks)
      if tasks.empty?
        p(class: "empty") { "Nothing upcoming." }
      else
        tasks_by_date = tasks.group_by { |t| t[:due_date] }

        ul(class: "task-list") do
          current_month = Date.today.month
          horizon = Date.today + 91
          past_horizon = false
          last_date = [tasks.last[:due_date], horizon].max
          (Date.today..last_date).each do |date|
            if date.month != current_month
              current_month = date.month
              li(class: "calendar-month", "x-show": "showEmpty") if date <= horizon
            end
            day_tasks = tasks_by_date[date]
            empty = day_tasks.nil?
            if empty && date > horizon
              unless past_horizon
                past_horizon = true
                li(class: "calendar-horizon", "x-show": "showEmpty") do
                  span { "3 months" }
                end
              end
              next
            end
            weekend = date.saturday? || date.sunday?
            day_attrs = { class: ["calendar-day", ("calendar-day-empty" if empty), ("calendar-day-weekend" if weekend)] }
            day_attrs[:"x-show"] = "showEmpty" if empty
            li(**day_attrs) do
              span(class: "calendar-date") { friendly_date(date) }
            end
            next if empty
            day_tasks.each do |task|
              li(class: ["task-item", ("calendar-day-weekend" if weekend)]) { task_card(task) }
            end
          end
        end
      end
    end

    def friendly_date(date)
      today = Date.today
      case date
      when today then "Today"
      when today + 1 then "Tomorrow"
      else
        if date < today + 7
          date.strftime("%A")
        else
          date.strftime("%b %-d")
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
