# frozen_string_literal: true

require "phlex"

module Views
  class TaskCard < Phlex::HTML
    def initialize(task:, csrf:, selected: false, sortable: false)
      @task = task
      @csrf = csrf
      @selected = selected
      @sortable = sortable
    end

    def view_template
      name = @task[:note].lines.first&.strip || @task[:note]
      overdue = @task[:due_date] < Date.today
      complete_path = "/series/#{@task[:series_id]}/tasks/#{@task[:id]}/complete"

      div(class: ["task-card", ("task-overdue" if overdue), ("task-selected" if @selected)]) do
        form(method: "post", action: complete_path, class: "complete-form") do
          input(type: "hidden", name: "_csrf", value: @csrf.call(complete_path))
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
