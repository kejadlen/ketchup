# frozen_string_literal: true

require "phlex"

require_relative "task_card"

module Views
  class OverdueColumn < Phlex::HTML
    def initialize(tasks:, selected_series: nil)
      @tasks = tasks
      @selected_series = selected_series
    end

    def view_template
      div(class: "column", "x-data": "sortable") do
        div(class: "column-header") do
          h2 { "Overdue" }
          nav(class: "sort-toggle") do
            button(
              "x-on:click": "sort = 'date'",
              "x-bind:class": "sort === 'date' && 'sort-active'",
              "x-bind:disabled": "sort === 'date'"
            ) { "Date" }
            button(
              "x-on:click": "sort = 'urgency'",
              "x-bind:class": "sort === 'urgency' && 'sort-active'",
              "x-bind:disabled": "sort === 'urgency'"
            ) { "Urgency" }
          end
        end

        if @tasks.empty?
          p(class: "empty") { "Nothing overdue." }
        else
          ul(class: "task-list") do
            @tasks.each do |task|
              li(
                class: "task-item",
                "data-urgency": format("%.4f", task.urgency),
                "data-due-date": task[:due_date].to_s
              ) do
                render TaskCard.new(task: task, selected: selected?(task), sortable: true)
              end
            end
          end
        end
      end
    end

    private

    def selected?(task)
      @selected_series && @selected_series.id == task[:series_id]
    end
  end
end
