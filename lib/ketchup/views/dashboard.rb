# frozen_string_literal: true

require "phlex"

require_relative "layout"
require_relative "overdue_column"
require_relative "upcoming_column"
require_relative "series_detail"
require_relative "new_series_form"
require_relative "user_form"

module Views
  INTERVAL_OPTIONS = Series::INTERVAL_UNITS.map { |u| [u, "#{u}(s)"] }.freeze

  class Dashboard < Phlex::HTML
    def initialize(current_user:, csrf:, series: nil, panel: nil)
      @current_user = current_user
      @csrf = csrf
      @series = series
      @panel = panel
    end

    def view_template
      render Layout.new(current_user: @current_user) do
        div(class: @series ? "home home--series" : "home") do
          render OverdueColumn.new(
            tasks: @current_user.overdue_tasks.all.sort_by { |t| -t.urgency },
            selected_series: @series,
            csrf: @csrf
          )
          render UpcomingColumn.new(
            tasks: @current_user.upcoming_tasks.all,
            selected_series: @series,
            csrf: @csrf
          )

          if @series
            render SeriesDetail.new(series: @series)
          elsif @panel == :user
            render UserForm.new(current_user: @current_user, csrf: @csrf)
          else
            render NewSeriesForm.new(csrf: @csrf)
          end
        end
      end
    end
  end
end
