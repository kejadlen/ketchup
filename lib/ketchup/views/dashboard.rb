# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Dashboard < Phlex::HTML
    def initialize(current_user:, series: nil)
      @current_user = current_user
      @series = series
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
            task_list(@current_user.overdue_tasks.all.sort_by { |t| -t.urgency }, empty: "Nothing overdue.", sortable: true)
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
            upcoming_list(@current_user.upcoming_tasks.all)
          end

          if @series
            series_detail_sidebar
          else
            new_series_sidebar
          end
        end
      end
    end

    private

    def series_detail_sidebar
      active_task = @series.active_task
      div(class: "column column-aside", "x-data": "{ editing: false }") do
        div(class: "column-header") do
          h2(class: "aside-heading") do
            a(href: "/", class: "aside-heading-action") { "New" }
          end
          button(
            class: "aside-heading-action",
            "x-show": "!editing",
            "x-on:click": "editing = true; $dispatch('start-editing')"
          ) { "Edit" }
          button(
            class: "aside-heading-action",
            "x-show": "editing",
            "x-on:click": "editing = false; $dispatch('stop-editing')"
          ) { "Done" }
        end

        div(class: "task-detail") do
          div(
            id: "series-note-detail",
            class: "task-detail-note",
            "data-value": @series.note || "",
            "data-series-id": @series.id.to_s
          )
          dl(class: "task-detail-fields") do
            dt { "Repeat every" }
            dd("x-show": "!editing") do
              plain interval_text(@series.interval_count, @series.interval_unit)
            end
            dd(
              class: "detail-edit-interval",
              "x-show": "editing",
              "x-cloak": true,
              "x-data": "intervalEditor(#{@series.id}, #{@series.interval_count}, '#{@series.interval_unit}')",
            ) do
              input(
                type: "number",
                class: "detail-input detail-input-count",
                min: 1,
                "x-model.number": "count",
                "x-on:change": "save()"
              )
              select(
                class: "detail-input detail-input-unit",
                "x-model": "unit",
                "x-on:change": "save()"
              ) do
                option(value: "day") { "day(s)" }
                option(value: "week") { "week(s)" }
                option(value: "month") { "month(s)" }
                option(value: "quarter") { "quarter(s)" }
                option(value: "year") { "year(s)" }
              end
            end

            if active_task
              dt { "Due date" }
              dd(
                "x-show": "!editing",
                "x-text": "new Date('#{active_task[:due_date]}T00:00').toLocaleDateString()"
              ) { active_task[:due_date].to_s }
              dd(
                "x-show": "editing",
                "x-cloak": true,
                "x-data": "dueDateEditor(#{@series.id}, '#{active_task[:due_date]}')"
              ) do
                input(
                  type: "date",
                  class: "detail-input detail-input-date",
                  "x-model": "dueDate",
                  "x-on:change": "save()"
                )
              end

              if active_task.urgency > 0
                dt { "Urgency" }
                dd { "#{format("%.1f", active_task.urgency)}x" }
              end
            end
          end

          unless @series.completed_tasks.empty?
            div(class: "task-history") do
              h3 { "History" }
              ul do
                @series.completed_tasks.each do |ct|
                  li(
                    class: "task-history-item",
                    "x-data": "historyNote(#{@series.id}, #{ct[:id]}, #{ct[:note] ? "true" : "false"})"
                  ) do
                    div(class: "task-history-row") do
                      span(class: "task-history-check") { "✓" }
                      span(class: "task-history-date") { ct[:completed_at].strftime("%Y-%m-%d") }
                      span(
                        class: "task-history-add-note",
                        "x-show": "!hasNote && !editing",
                        "x-on:click": "edit()"
                      ) { "add a note..." }
                    end
                    div(
                      class: "task-history-note-editor",
                      "data-value": ct[:note] || "",
                      "x-show": "hasNote || editing",
                      "x-ref": "editor"
                    )
                  end
                end
              end
            end
          end
        end
      end
    end

    def new_series_sidebar
      div(class: "column column-aside") do
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
                option(value: "day", selected: true) { "day(s)" }
                option(value: "week") { "week(s)" }
                option(value: "month") { "month(s)" }
                option(value: "quarter") { "quarter(s)" }
                option(value: "year") { "year(s)" }
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
          last_date = tasks.last[:due_date]
          last_task_in_window = tasks_by_date.keys.select { |d| d <= horizon }.max || (Date.today - 1)
          (Date.today..last_date).each do |date|
            day_tasks = tasks_by_date[date]
            empty = day_tasks.nil?
            next if empty && date > last_task_in_window && date <= horizon
            if date.month != current_month
              current_month = date.month
              li(class: "calendar-month", "x-show": "showEmpty") if date <= horizon
            end
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
      selected = @series && @series.id == task[:series_id]

      div(class: ["task-card", ("task-overdue" if overdue), ("task-selected" if selected)]) do
        form(method: "post", action: "/series/#{task[:series_id]}/tasks/#{task[:id]}/complete", class: "complete-form") do
          button(
            type: "submit", title: "Complete",
            class: "complete-btn",
            **{ "aria-label": "Complete #{name}" }
          ) { "✓" }
        end
        a(href: "/series/#{task[:series_id]}", class: "task-name") { name }
        if sortable && overdue
          span(class: "task-secondary task-urgency", "x-show": "sort === 'urgency'") { "#{format("%.1f", task.urgency)}x" } if task.urgency > 0
          span(class: "task-secondary", "x-show": "sort === 'date'") { task[:due_date].to_s }
        end
      end
    end

    def interval_text(count, unit)
      "#{count} #{count == 1 ? unit : "#{unit}s"}"
    end
  end
end
