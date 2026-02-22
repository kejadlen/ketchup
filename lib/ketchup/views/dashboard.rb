# frozen_string_literal: true

require "phlex"

require_relative "layout"
require_relative "task_list"

module Views
  INTERVAL_OPTIONS = Series::INTERVAL_UNITS.map { |u| [u, "#{u}(s)"] }.freeze

  class Dashboard < Phlex::HTML
    def initialize(current_user:, csrf:)
      @current_user = current_user
      @csrf = csrf
    end

    def view_template
      render Layout.new(current_user: @current_user) do
        div(class: "dashboard") do
          render_main_column
        end
      end
    end

    private

    def render_main_column
      overdue = @current_user.overdue_tasks.all.sort_by { |t| -t.urgency }
      upcoming = @current_user.upcoming_tasks.all

      div(class: "main-column") do
        render TaskList.new(
          overdue: overdue,
          upcoming: upcoming,
          csrf: @csrf
        )
      end
    end
  end
end
