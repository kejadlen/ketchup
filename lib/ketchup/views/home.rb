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

          div(class: "column column-aside", "x-data": "") do
            div(class: "column-header") do
              h2(class: "aside-heading") do
                span("x-show": "$store.sidebar.mode === 'form'") { "New Series" }
              end
              nav(class: "sort-toggle") do
                button(
                  "x-on:click": "$store.sidebar.toggleForm()",
                  "x-bind:class": "$store.sidebar.mode === 'form' && 'sort-active'"
                ) { "+ New" }
              end
            end

            div(class: "task-detail", "x-show": "$store.sidebar.mode === 'task'") do
              p(class: "task-detail-note", "x-text": "$store.sidebar.taskNote")
              dl(class: "task-detail-fields") do
                dt { "Interval" }
                dd("x-text": "$store.sidebar.taskInterval")

                dt { "Due date" }
                dd("x-text": "$store.sidebar.taskDueDate")

                dt("x-show": "$store.sidebar.taskUrgency !== ''") { "Urgency" }
                dd("x-show": "$store.sidebar.taskUrgency !== ''", "x-text": "$store.sidebar.taskUrgency")
              end
            end

            form(method: "post", action: "/series", "x-show": "$store.sidebar.mode === 'form'") do
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
            li(**attrs) { task_card(task, sortable: sortable) }
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

    def task_card(task, sortable: false)
      name = task[:note].lines.first&.strip || task[:note]
      overdue = task[:due_date] < Date.today

      div(
        class: ["task-card", ("task-overdue" if overdue)],
        "x-on:click": "$store.sidebar.showTask($el)",
        "x-bind:class": "$store.sidebar.taskId == '#{task[:id]}' && 'task-selected'",
        "data-task-id": task[:id].to_s,
        "data-task-name": name,
        "data-task-note": task[:note],
        "data-task-interval": interval_text(task[:interval_count], task[:interval_unit]),
        "data-task-due-date": task[:due_date].to_s,
        "data-task-urgency": task.urgency > 0 ? "#{format("%.1f", task.urgency)}x" : "",
        "data-task-overdue": overdue.to_s
      ) do
        form(method: "post", action: "/tasks/#{task[:id]}/complete", class: "complete-form") do
          button(
            type: "submit", title: "Complete",
            "x-on:click.stop": "",
            **{ "aria-label": "Complete #{name}" }
          ) { "✓" }
        end
        span(class: "task-name") { name }
        if sortable && overdue
          span(class: "task-secondary task-urgency", "x-show": "sort === 'urgency'") { "#{format("%.1f", task.urgency)}x" } if task.urgency > 0
          span(class: "task-secondary", "x-show": "sort === 'date'") { task[:due_date].to_s }
        end
      end
    end

    def interval_text(count, unit)
      "Every #{count} #{count == 1 ? unit : "#{unit}s"}"
    end
  end
end
