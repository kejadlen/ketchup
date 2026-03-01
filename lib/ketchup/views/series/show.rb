# frozen_string_literal: true

require "phlex"

require_relative "../layout"

module Views
  module Series
    class Show < Phlex::HTML
      def initialize(series:, current_user:, csrf:)
        @series = series
        @current_user = current_user
        @csrf = csrf
      end

      def view_template
        active_task = @series.active_task

        render Layout.new(current_user: @current_user, title: "#{note_title} — Ketchup", active_view: nil) do
          div(class: "dashboard") do
            div(class: "main-column") do
              section(class: "section", "x-data": "{ editing: false }") do
                div(class: "section-header") do
                  h2(class: "section-title") do
                    span(class: "section-title-text") { "Series" }
                  end
                  button(
                    class: "section-edit-btn",
                    "x-show": "!editing",
                    "x-on:click": "editing = true; $dispatch('start-editing')"
                  ) do
                    plain "Edit"
                  end
                  button(
                    class: "section-edit-btn section-edit-btn--cancel",
                    "x-show": "editing",
                    "x-cloak": true,
                    "x-on:click": "editing = false; location.reload()"
                  ) do
                    plain "Cancel"
                  end
                  button(
                    class: "section-edit-btn",
                    "x-show": "editing",
                    "x-cloak": true,
                    "x-on:click": "editing = false; $dispatch('stop-editing')"
                  ) do
                    plain "Save"
                  end
                end

                div(class: "series-note", id: "series-note-detail",
                    "x-bind:class": "{ 'series-note--editable': editing }",
                    "data-value": @series.note || "",
                    "data-series-id": @series.id.to_s)

                dl(class: "detail-fields") do
                  dt { "Repeat every" }
                  dd("x-show": "!editing") do
                    plain interval_text(@series.interval_count, @series.interval_unit)
                  end
                  dd(
                    class: "detail-edit-interval",
                    "x-show": "editing",
                    "x-cloak": true,
                    "x-data": "intervalEditor(#{@series.id}, #{@series.interval_count}, '#{@series.interval_unit}')"
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

                end

                if active_task
                  complete_path = "/series/#{@series.id}/tasks/#{active_task.id}/complete"
                  form(method: "post", action: complete_path, class: "current-task") do
                    input(type: "hidden", name: "_csrf", value: @csrf.call(complete_path))
                    input(type: "hidden", name: "return_to", value: "/series/#{@series.id}")
                    div(class: "section-header") do
                      h2(class: "section-title") do
                        span(class: "section-title-text") { "Current task" }
                      end
                      button(type: "submit", class: "section-edit-btn") { "Complete" }
                    end
                    dl(class: "detail-fields") do
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
                        dt(class: "detail-overdue") { "Urgency" }
                        dd(class: "detail-overdue") { "#{format("%.1f", active_task.urgency)}x" }
                      end

                      dt { "Completed on" }
                      dd do
                        input(
                          type: "date",
                          name: "completed_date",
                          class: "detail-input detail-input-date",
                          "x-data": true,
                          "x-init": "$el.value = new Date().toISOString().slice(0, 10)"
                        )
                      end
                    end
                  end
                end

                unless @series.completed_tasks.empty?
                  div(class: "task-history") do
                    div(class: "section-header") do
                      h2(class: "section-title") do
                        span(class: "section-title-text") { "History" }
                      end
                    end
                    ul do
                      @series.completed_tasks.each do |ct|
                        completed_date = ct[:completed_at].strftime("%Y-%m-%d")
                        li(
                          class: "task-history-item",
                          "x-data": "{ ...historyNote(#{@series.id}, #{ct[:id]}, #{ct[:note] ? "true" : "false"}), ...completedDateEditor(#{@series.id}, #{ct[:id]}, '#{completed_date}') }"
                        ) do
                          div(class: "task-history-row") do
                            span(class: "task-history-check") { "✓" }
                            span(
                              class: "task-history-date",
                              "x-show": "!editingDate",
                              "x-on:click": "editingDate = true; $nextTick(() => $refs.dateInput.focus())",
                              "x-text": "new Date(completedDate + 'T00:00').toLocaleDateString()"
                            ) { completed_date }
                            input(
                              type: "date",
                              class: "task-history-date-input",
                              "x-show": "editingDate",
                              "x-cloak": true,
                              "x-model": "completedDate",
                              "x-ref": "dateInput",
                              "x-on:blur": "save()",
                              "x-on:keydown.enter": "$el.blur()",
                              "x-on:keydown.escape": "completedDate = '#{completed_date}'; editingDate = false"
                            )
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
        end
      end

      private

      def note_title
        @series.note&.lines&.first&.strip || "Series"
      end

      def interval_text(count, unit)
        "#{count} #{count == 1 ? unit : "#{unit}s"}"
      end
    end
  end
end
