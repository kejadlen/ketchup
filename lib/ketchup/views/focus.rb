# frozen_string_literal: true

require "phlex"

require_relative "layout"

module Views
  class Focus < Phlex::HTML
    def initialize(current_user:, task:, csrf:, position:, total:)
      @current_user = current_user
      @task = task
      @csrf = csrf
      @position = position
      @total = total
    end

    def view_template
      render Layout.new(current_user: @current_user, active_view: :focus) do
        div(class: "focus-view") do
          render_progress
          render_task
          render_complete_button
        end
      end
    end

    private

    def render_progress
      div(class: "focus-progress") do
        plain "#{@position} of #{@total} overdue"
      end
    end

    def render_task
      name = @task[:note].lines.first&.strip || @task[:note]
      interval_count = @task[:interval_count] || @task.series.interval_count
      interval_unit = @task[:interval_unit] || @task.series.interval_unit
      interval = "#{interval_count} #{interval_count == 1 ? interval_unit : "#{interval_unit}s"}"

      div(class: "focus-task") do
        div(class: "focus-urgency") do
          plain "#{format("%.1f", @task.urgency)}x overdue"
        end
        h1(class: "focus-name") { name }
        p(class: "focus-interval") { "every #{interval}" }
      end
    end

    def render_complete_button
      complete_path = "/series/#{@task[:series_id]}/tasks/#{@task[:id]}/complete"
      form(method: "post", action: complete_path, class: "focus-form") do
        input(type: "hidden", name: "_csrf", value: @csrf.call(complete_path))
        input(type: "hidden", name: "return_to", value: "/focus")
        button(type: "submit", class: "focus-complete-btn") do
          span { "\u2713" }
          plain " Done"
        end
      end
    end
  end
end
