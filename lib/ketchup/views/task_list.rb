# frozen_string_literal: true

require "phlex"

require_relative "task_card"

module Views
  class TaskList < Phlex::HTML
    def initialize(overdue:, upcoming:, csrf:, selected_series: nil)
      @overdue = overdue
      @upcoming = upcoming
      @csrf = csrf
      @selected_series = selected_series
    end

    def view_template
      div(class: "task-list-container", "x-data": "") do
        render_overdue
        render_upcoming
        render_completed_today
      end
    end

    private

    def render_overdue
      section(class: "section section--overdue") do
        div(class: "section-header") do
          h2(class: "section-title") do
            span(class: "section-title-text") do
              plain "Overdue"
              unless @overdue.empty?
                plain " (#{@overdue.size})"
              end
            end
          end
        end

        if @overdue.empty?
          p(class: "empty") { "All caught up!" }
        else
          ul(class: "task-list") do
            @overdue.each do |task|
              li(class: "task-item") do
                render TaskCard.new(task: task, csrf: @csrf, selected: selected?(task), overdue: true)
              end
            end
          end
        end
      end
    end

    def render_upcoming
      section(class: "section section--upcoming") do
        div(class: "section-header") do
          h2(class: "section-title") do
            span(class: "section-title-text") { "Coming up" }
          end
        end

        if @upcoming.empty?
          p(class: "empty") { "Nothing upcoming." }
        else
          tasks_by_date = @upcoming.group_by { |t| t[:due_date] }

          ul(class: "task-list") do
            tasks_by_date.each do |date, tasks|
              li(class: "date-header") do
                span(class: "date-label") { friendly_date(date) }
              end
              tasks.each do |task|
                li(class: "task-item") do
                  render TaskCard.new(task: task, csrf: @csrf, selected: selected?(task), overdue: false)
                end
              end
            end
          end
        end
      end
    end

    def render_completed_today
      # Placeholder for future "completed today" counter
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
