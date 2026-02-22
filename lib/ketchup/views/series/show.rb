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
              section(class: "section") do
                div(class: "section-header") do
                  h2(class: "section-title") do
                    span(class: "section-title-text") { "Series" }
                  end
                end

                div(class: "series-note", id: "series-note-detail",
                    "data-value": @series.note || "",
                    "data-series-id": @series.id.to_s)

                dl(class: "detail-fields") do
                  dt { "Repeat every" }
                  dd { interval_text(@series.interval_count, @series.interval_unit) }

                  if active_task
                    dt { "Due date" }
                    dd { active_task[:due_date].to_s }

                    if active_task.urgency > 0
                      dt { "Urgency" }
                      dd { "#{format("%.1f", active_task.urgency)}×" }
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
