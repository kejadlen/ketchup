# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Agenda < Phlex::HTML
    DAYS = 7

    def initialize(current_user:, csrf:)
      @current_user = current_user
      @csrf = csrf
    end

    def view_template
      today = Date.today
      dates = (0...DAYS).map { |i| today + i }
      end_date = dates.last

      overdue = @current_user.overdue_tasks.all.sort_by { |t| -t.urgency }
      upcoming = @current_user.upcoming_tasks
        .where { due_date <= end_date }
        .all

      tasks_by_date = {}
      upcoming.each { |t| (tasks_by_date[t[:due_date]] ||= []) << t }

      render Layout.new(current_user: @current_user, active_view: :agenda) do
        div(class: "agenda-view") do
          div(class: "agenda-columns") do
            render_overdue_column(overdue)
            dates.each_with_index do |date, i|
              render_day_column(date, tasks_by_date[date] || [], i == 0)
            end
          end
        end
      end
    end

    private

    def render_overdue_column(tasks)
      div(class: "agenda-column agenda-overdue") do
        div(class: "agenda-column-header agenda-column-header--overdue") { "Overdue" }
        if tasks.empty?
          p(class: "empty") { "All clear" }
        else
          tasks.each { |t| render_task_pill(t, overdue: true) }
        end
      end
    end

    def render_day_column(date, tasks, is_today)
      label = if is_today
                "Today"
              elsif date == Date.today + 1
                "Tomorrow"
              else
                date.strftime("%a %-d")
              end

      div(class: ["agenda-column", ("agenda-column--today" if is_today)]) do
        div(class: "agenda-column-header") { label }
        tasks.each { |t| render_task_pill(t, overdue: false) }
      end
    end

    def render_task_pill(task, overdue:)
      name = task[:note].lines.first&.strip || task[:note]
      a(
        href: "/series/#{task[:series_id]}",
        class: ["agenda-pill", ("agenda-pill--overdue" if overdue)],
        "x-on:click.prevent": "$dispatch('open-panel', { seriesId: #{task[:series_id]} })"
      ) { name }
    end
  end
end
