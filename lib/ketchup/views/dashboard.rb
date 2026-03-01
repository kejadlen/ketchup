# frozen_string_literal: true

require "phlex"

require_relative "layout"
require_relative "task_card"

module Views
  INTERVAL_OPTIONS = Series::INTERVAL_UNITS.map { |u| [u, "#{u}(s)"] }.freeze

  AGENDA_DAYS = 7

  class Dashboard < Phlex::HTML
    def initialize(current_user:, csrf:, flash: nil)
      @current_user = current_user
      @csrf = csrf
      @flash = flash
    end

    def view_template
      overdue = @current_user.overdue_tasks.all.sort_by { |t| -t.urgency }
      upcoming = @current_user.upcoming_tasks.all

      render Layout.new(current_user: @current_user, flash: @flash) do
        div(class: "dashboard") do
          div(class: "column-overdue") do
            render_focus(overdue)
            render_overdue(overdue.drop(1))
          end
          div(class: "column-agenda") do
            render_agenda(upcoming, overdue_count: overdue.size)
          end
        end
      end
    end

    private

    def render_focus(overdue)
      if overdue.empty?
        section(class: "section section--focus") do
          p(class: "empty") { "All caught up!" }
        end
        return
      end

      task = overdue.first

      section(class: "section section--focus") do
        div(class: "section-header") do
          h2(class: "section-title") do
            span(class: "section-title-text") { "Next up" }
          end
        end
        render TaskCard.new(task: task, csrf: @csrf, overdue: true)
      end
    end

    def render_overdue(tasks)
      return if tasks.empty?

      section(class: "section section--overdue") do
        div(class: "section-header") do
          h2(class: "section-title") do
            span(class: "section-title-text") { "Overdue (#{tasks.size})" }
          end
        end

        ul(class: "task-list") do
          tasks.each do |task|
            li(class: "task-item") do
              render TaskCard.new(task: task, csrf: @csrf, overdue: true)
            end
          end
        end
      end
    end

    def render_agenda(upcoming, overdue_count: 0)
      tasks_by_date = {}
      upcoming.each { |t| (tasks_by_date[t[:due_date]] ||= []) << t }

      today = Date.today

      section(class: "section section--agenda") do
        div(class: "agenda-week") do
          if overdue_count > 0
            div(class: "agenda-week-day agenda-week-day--overdue") do
              span(class: "agenda-week-label") { "!" }
              span(class: "agenda-week-count") { overdue_count.to_s }
            end
          end

          AGENDA_DAYS.times do |i|
            date = today + i
            count = (tasks_by_date[date] || []).size
            classes = ["agenda-week-day"]
            classes << "agenda-week-day--today" if i == 0
            classes << "agenda-week-day--has-tasks" if count > 0

            div(class: classes) do
              span(class: "agenda-week-label") { date.strftime("%a") }
              span(class: "agenda-week-count") { count.to_s } if count > 0
            end
          end
        end

        tasks_by_date.keys.sort.each do |date|
          day_tasks = tasks_by_date[date]
          offset = (date - today).to_i

          div(class: ["agenda-day", ("agenda-day--today" if offset == 0)]) do
            div(class: "agenda-day-header") { friendly_day(date, offset) }
            day_tasks.each do |task|
              task_name = task[:note].lines.first&.strip || task[:note]
              complete_path = "/series/#{task[:series_id]}/tasks/#{task[:id]}/complete"

              div(class: "agenda-task") do
                form(method: "post", action: complete_path, class: "complete-form") do
                  input(type: "hidden", name: "_csrf", value: @csrf.call(complete_path))
                  input(type: "hidden", name: "return_to", value: "/")
                  button(type: "submit", title: "Complete", class: "complete-btn",
                         **{ "aria-label": "Complete #{task_name}" }) { "\u2713" }
                end
                a(href: "/series/#{task[:series_id]}", class: "agenda-day-pill") { task_name }
              end
            end
          end
        end
      end
    end

    def friendly_day(date, offset)
      case offset
      when 0 then "Today"
      when 1 then "Tomorrow"
      else date.strftime("%a, %b %-d")
      end
    end
  end
end
