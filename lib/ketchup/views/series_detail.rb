# frozen_string_literal: true

require "phlex"

module Views
  class SeriesDetail < Phlex::HTML
    def initialize(series:, csrf: nil)
      @series = series
      @csrf = csrf
    end

    def view_template
      active_task = @series.active_task
      div(class: "panel-inner", "x-data": "{ editing: false }") do
        div(class: "panel-header") do
          a(href: "/", class: "panel-close", "aria-label": "Close") { "←" }
          div(class: "panel-actions") do
            button(
              class: "panel-action",
              "x-show": "!editing",
              "x-on:click": "editing = true; $dispatch('start-editing')"
            ) { "Edit" }
            button(
              class: "panel-action",
              "x-show": "editing",
              "x-on:click": "editing = false; $dispatch('stop-editing')"
            ) { "Done" }
          end
        end

        div(class: "panel-body") do
          div(
            id: "series-note-detail",
            class: "series-note",
            "data-value": @series.note || "",
            "data-series-id": @series.id.to_s
          )

          dl(class: "detail-fields") do
            dt { "Repeat every" }
            dd("x-show": "!editing") do
              plain interval_text(@series.interval_count, @series.interval_unit)
            end
            dd(
              class: "detail-edit-interval",
              "x-show": "editing",
              "x-cloak": true,
              "x-data": "intervalEditor(#{@series.id}, #{@series.interval_count}, '#{@series.interval_unit}')",
            ) do
              input(
                type: "number",
                class: "detail-input detail-input-count",
                min: 1,
                "x-model.number": "count",
                "x-on:change": "save()"
              )
              select(
                class: "detail-input detail-input-unit",
                "x-model": "unit",
                "x-on:change": "save()"
              ) do
                INTERVAL_OPTIONS.each { |val, label| option(value: val) { label } }
              end
            end

            if active_task
              dt { "Due date" }
              dd(
                "x-show": "!editing",
                "x-text": "new Date('#{active_task[:due_date]}T00:00').toLocaleDateString()"
              ) { active_task[:due_date].to_s }
              dd(
                "x-show": "editing",
                "x-cloak": true,
                "x-data": "dueDateEditor(#{@series.id}, '#{active_task[:due_date]}')"
              ) do
                input(
                  type: "date",
                  class: "detail-input detail-input-date",
                  "x-model": "dueDate",
                  "x-on:change": "save()"
                )
              end

              if active_task.urgency > 0
                dt { "Urgency" }
                dd { "#{format("%.1f", active_task.urgency)}×" }
              end
            end
          end

          unless @series.completed_tasks.empty?
            div(class: "task-history") do
              h3 { "History" }
              ul do
                @series.completed_tasks.each do |ct|
                  li(
                    class: "task-history-item",
                    "x-data": "historyNote(#{@series.id}, #{ct[:id]}, #{ct[:note] ? "true" : "false"})"
                  ) do
                    div(class: "task-history-row") do
                      span(class: "task-history-check") { "✓" }
                      span(class: "task-history-date") { ct[:completed_at].strftime("%Y-%m-%d") }
                      span(
                        class: "task-history-add-note",
                        "x-show": "!hasNote && !editing",
                        "x-on:click": "edit()"
                      ) { "add a note..." }
                    end
                    div(
                      class: "task-history-note-editor",
                      "data-value": ct[:note] || "",
                      "x-show": "hasNote || editing",
                      "x-ref": "editor"
                    )
                  end
                end
              end
            end
          end
        end
      end
    end

    private

    def interval_text(count, unit)
      "#{count} #{count == 1 ? unit : "#{unit}s"}"
    end
  end
end
