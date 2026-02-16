# frozen_string_literal: true

require "phlex"

require_relative "task_card"

module Views
  class UpcomingColumn < Phlex::HTML
    def initialize(tasks:, selected_series: nil)
      @tasks = tasks
      @selected_series = selected_series
    end

    def view_template
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

        if @tasks.empty?
          p(class: "empty") { "Nothing upcoming." }
        else
          render_calendar
        end
      end
    end

    private

    def render_calendar
      tasks_by_date = @tasks.group_by { |t| t[:due_date] }

      ul(class: "task-list") do
        current_month = Date.today.month
        horizon = Date.today + 91
        past_horizon = false
        last_date = @tasks.last[:due_date]
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
            li(class: ["task-item", ("calendar-day-weekend" if weekend)]) do
              render TaskCard.new(task: task, selected: selected?(task))
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

    def selected?(task)
      @selected_series && @selected_series.id == task[:series_id]
    end
  end
end
