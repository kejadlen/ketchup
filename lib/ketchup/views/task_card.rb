# frozen_string_literal: true

require "phlex"

module Views
  class TaskCard < Phlex::HTML
    def initialize(task:, csrf:, selected: false, overdue: false)
      @task = task
      @csrf = csrf
      @selected = selected
      @overdue = overdue
    end

    def view_template
      name = @task[:note].lines.first&.strip || @task[:note]
      complete_path = "/series/#{@task[:series_id]}/tasks/#{@task[:id]}/complete"

      div(class: task_classes) do
        form(method: "post", action: complete_path, class: "complete-form") do
          input(type: "hidden", name: "_csrf", value: @csrf.call(complete_path))
          button(
            type: "submit", title: "Complete",
            class: "complete-btn",
            **{ "aria-label": "Complete #{name}" }
          ) { "✓" }
        end
        div(class: "task-body") do
          a(href: "/series/#{@task[:series_id]}", class: "task-name") { name }
          if @overdue
            span(class: "task-meta") do
              plain meta_text
            end
          end
        end
        if @overdue && @task.urgency > 0
          span(class: "task-urgency", "x-show": "sort === 'urgency'") { "#{format("%.1f", @task.urgency)}×" }
          span(class: "task-date", "x-show": "sort === 'date'") { @task[:due_date].to_s }
        end
      end
    end

    private

    def task_classes
      classes = ["task-card"]
      classes << "task-card--overdue" if @overdue
      classes << "task-card--selected" if @selected
      classes
    end

    def meta_text
      days = (Date.today - @task[:due_date]).to_i
      interval_count = @task[:interval_count] || @task.series.interval_count
      interval_unit = @task[:interval_unit] || @task.series.interval_unit
      interval = "#{interval_count} #{interval_count == 1 ? interval_unit : "#{interval_unit}s"}"

      ago = if days == 1
              "yesterday"
            elsif days < 7
              "#{days} days ago"
            elsif days < 30
              weeks = days / 7
              "#{weeks} #{weeks == 1 ? "week" : "weeks"} ago"
            else
              months = days / 30
              "#{months} #{months == 1 ? "month" : "months"} ago"
            end

      "every #{interval} · #{ago}"
    end
  end
end
