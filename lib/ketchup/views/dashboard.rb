# frozen_string_literal: true

require "phlex"

require_relative "layout"
require_relative "task_list"
require_relative "series_detail"
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
      has_panel = @series || @panel == :user
      render Layout.new(current_user: @current_user, panel_open: has_panel) do
        div(class: "dashboard") do
          render_main_column
          render_panel if has_panel
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
          selected_series: @series,
          csrf: @csrf
        )
      end
    end

    def render_panel
      div(
        class: "panel",
        id: "panel",
        "x-data": "panel",
        "x-bind:class": "open && 'panel--open'"
      ) do
        div(class: "panel-backdrop", "x-on:click": "close()")

        div(class: "panel-content") do
          if @series
            render SeriesDetail.new(series: @series, csrf: @csrf)
          elsif @panel == :user
            render UserForm.new(current_user: @current_user, csrf: @csrf)
          end
        end
      end
    end
  end
end
