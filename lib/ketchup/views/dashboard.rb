# frozen_string_literal: true

require "phlex"

require_relative "layout"
require_relative "task_list"

module Views
  INTERVAL_OPTIONS = Series::INTERVAL_UNITS.map { |u| [u, "#{u}(s)"] }.freeze

  class Dashboard < Phlex::HTML
    def initialize(current_user:, csrf:, series: nil, open_user: false)
      @current_user = current_user
      @csrf = csrf
      @series = series
      @open_user = open_user
    end

    def view_template
      render Layout.new(current_user: @current_user) do
        div(
          class: "dashboard",
          **dashboard_data_attrs
        ) do
          render_main_column
        end
      end
    end

    private

    def dashboard_data_attrs
      if @series
        { "data-open-series": @series.id.to_s }
      elsif @open_user
        { "data-open-user": @current_user[:id].to_s }
      else
        {}
      end
    end

    def render_main_column
      overdue = @current_user.overdue_tasks.all.sort_by { |t| -t.urgency }
      upcoming = @current_user.upcoming_tasks.all

      div(class: "main-column") do
        render TaskList.new(
          overdue: overdue,
          upcoming: upcoming,
          selected_series: @series,
          csrf: @csrf
        )
      end
    end
  end
end
