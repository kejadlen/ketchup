# frozen_string_literal: true

require "phlex"
require "date"

require_relative "layout"

module Views
  class Calendar < Phlex::HTML
    def initialize(current_user:, csrf:, date: Date.today)
      @current_user = current_user
      @csrf = csrf
      @date = date
    end

    def view_template
      first_of_month = Date.new(@date.year, @date.month, 1)
      last_of_month = Date.new(@date.year, @date.month, -1)
      prev_month = first_of_month << 1
      next_month = first_of_month >> 1

      overdue = @current_user.overdue_tasks.all
      upcoming = @current_user.upcoming_tasks
        .where { due_date <= last_of_month }
        .all

      tasks_by_date = {}
      overdue.each { |t| (tasks_by_date[Date.today] ||= []) << [t, true] }
      upcoming.each { |t| (tasks_by_date[t[:due_date]] ||= []) << [t, false] }

      render Layout.new(current_user: @current_user, active_view: :calendar) do
        div(class: "calendar-view") do
          div(class: "calendar-header") do
            a(href: "/calendar?date=#{prev_month}", class: "calendar-nav") { "\u2190" }
            h2(class: "calendar-month-title") { first_of_month.strftime("%B %Y") }
            a(href: "/calendar?date=#{next_month}", class: "calendar-nav") { "\u2192" }
          end

          div(class: "calendar-grid") do
            %w[Mon Tue Wed Thu Fri Sat Sun].each do |day_name|
              div(class: "calendar-day-name") { day_name }
            end

            start_dow = (first_of_month.wday - 1) % 7
            start_dow.times { div(class: "calendar-day calendar-day--empty") }

            (1..last_of_month.day).each do |day_num|
              date = Date.new(@date.year, @date.month, day_num)
              is_today = date == Date.today
              day_tasks = tasks_by_date[date] || []

              div(class: ["calendar-day", ("calendar-day--today" if is_today)]) do
                span(class: "calendar-day-num") { day_num.to_s }
                day_tasks.each do |task, is_overdue|
                  task_name = task[:note].lines.first&.strip || task[:note]
                  a(
                    href: "/series/#{task[:series_id]}",
                    class: ["calendar-pill", ("calendar-pill--overdue" if is_overdue)]
                  ) { task_name }
                end
              end
            end
          end
        end
      end
    end
  end
end
