# frozen_string_literal: true

require "phlex"

module Views
  class TaskCard < Phlex::HTML
    def initialize(task:, selected: false, sortable: false)
      @task = task
      @selected = selected
      @sortable = sortable
    end

    def view_template
      name = @task[:note].lines.first&.strip || @task[:note]
      overdue = @task[:due_date] < Date.today

      div(class: ["task-card", ("task-overdue" if overdue), ("task-selected" if @selected)]) do
        form(method: "post", action: "/series/#{@task[:series_id]}/tasks/#{@task[:id]}/complete", class: "complete-form") do
          button(
            type: "submit", title: "Complete",
            class: "complete-btn",
            **{ "aria-label": "Complete #{name}" }
          ) { "✓" }
        end
        a(href: "/series/#{@task[:series_id]}", class: "task-name") { name }
        if @sortable && overdue
          span(class: "task-secondary task-urgency", "x-show": "sort === 'urgency'") { "#{format("%.1f", @task.urgency)}x" } if @task.urgency > 0
          span(class: "task-secondary", "x-show": "sort === 'date'") { @task[:due_date].to_s }
        end
      end
    end
  end
end
