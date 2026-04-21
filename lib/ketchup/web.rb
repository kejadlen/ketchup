# frozen_string_literal: true

require "json"
require "roda"

require_relative "models"
require_relative "views/dashboard"
require_relative "views/series/new"
require_relative "views/series/show"
require_relative "views/user/show"

module Ketchup
  class Web < Roda
    plugin :halt
    plugin :static, %w[ /css /js /favicon.svg /snapshots ]
    plugin :all_verbs
    plugin :sessions, secret: CONFIG.session_secret
    plugin :route_csrf, csrf_failure: :empty_403, check_request_methods: %w[POST]
    plugin :error_handler do |e|
      case e
      when Sequel::NoMatchingRow
        response.status = 404
        ""
      else
        raise
      end
    end

    def current_user
      rack_header = "HTTP_#{CONFIG.auth_header.upcase.tr("-", "_")}"
      login = env[rack_header]
      return unless login

      User.find_or_create(login: login)
    end

    route do |r|
      @user = current_user
      r.halt 403 unless @user

      check_csrf!

      r.root do
        flash = session.delete("flash")
        Views::Dashboard.new(current_user: @user, csrf: method(:csrf_token), flash: flash).call
      end

      r.on "users", Integer do |user_id|
        r.halt 404 unless @user.id == user_id

        r.get do
          Views::User::Show.new(current_user: @user, csrf: method(:csrf_token)).call
        end

        r.post "email" do
          email = r.params["email"].to_s.strip
          @user.update(email: email.empty? ? nil : email)
          r.redirect "/users/#{user_id}"
        end
      end

      r.on "series" do
        r.get "new" do
          Views::Series::New.new(current_user: @user, csrf: method(:csrf_token)).call
        end

        r.is do
          r.post do
            note = r.params["note"].to_s.strip
            interval_unit = r.params["interval_unit"].to_s
            interval_count = r.params["interval_count"].to_i
            first_due_date = r.params["first_due_date"].to_s

            r.halt 422 if note.empty?
            r.halt 422 unless Series::INTERVAL_UNITS.include?(interval_unit)
            r.halt 422 unless interval_count >= 1

            begin
              due_date = Date.parse(first_due_date)
            rescue Date::Error
              r.halt 422
            end

            series = Series.create_with_first_task(
              user: @user,
              note: note,
              interval_unit: interval_unit,
              interval_count: interval_count,
              first_due_date: due_date
            )

            r.redirect "/series/#{series.id}"
          end
        end

        r.on Integer do |series_id|
          @series = @user.series_dataset.where(id: series_id).sole

          r.on "archive" do
            r.post do
              DB.transaction do
                @series.active_task&.destroy
                @series.update(archived_at: Time.now)
              end

              note_title = @series.note.lines.first&.strip || @series.note
              archive_path = "/series/#{series_id}/archive"
              session["flash"] = {
                "message" => "Archived",
                "title" => note_title,
                "path" => "/series/#{series_id}",
                "undo_path" => archive_path
              }
              r.redirect "/"
            end

            r.delete do
              DB.transaction do
                @series.update(archived_at: nil)
                unless @series.active_task
                  last_completed = @series.completed_tasks.first
                  due_date = last_completed ? @series.next_due_date(last_completed[:completed_at].to_date) : Date.today
                  Task.create(series_id: @series.id, due_date: due_date)
                end
              end
              r.halt 204
            end
          end

          r.is do
            r.get do
              Views::Series::Show.new(series: @series, current_user: @user, csrf: method(:csrf_token)).call
            end

            r.patch do
              updates = {}

              if r.params.key?("note")
                note = r.params["note"].to_s.strip
                r.halt 422 if note.empty?
                updates[:note] = note
              end

              if r.params.key?("interval_count") || r.params.key?("interval_unit")
                interval_count = r.params.key?("interval_count") ? r.params["interval_count"].to_i : @series.interval_count
                interval_unit = r.params.key?("interval_unit") ? r.params["interval_unit"].to_s : @series.interval_unit
                r.halt 422 unless Series::INTERVAL_UNITS.include?(interval_unit)
                r.halt 422 unless interval_count >= 1
                updates[:interval_count] = interval_count
                updates[:interval_unit] = interval_unit
              end

              @series.update(updates) unless updates.empty?

              response["content-type"] = "application/json"
              updates.transform_keys(&:to_s).to_json
            end
          end

          r.on "tasks", Integer do |task_id|
            @task = @series.tasks_dataset.where(id: task_id).sole

            r.on "complete" do
              r.post do
                r.halt 422 unless @task[:completed_at].nil?

                @task.complete!(completed_on: Date.today)

                note_title = @series.note.lines.first&.strip || @series.note
                complete_path = "/series/#{series_id}/tasks/#{@task.id}/complete"
                session["flash"] = {
                  "message" => "Completed",
                  "title" => note_title,
                  "path" => "/series/#{series_id}",
                  "undo_path" => complete_path
                }

                return_to = r.params["return_to"]
                if return_to && return_to.start_with?("/")
                  r.redirect return_to
                else
                  r.redirect "/"
                end
              end

              r.delete do
                r.halt 422 if @task[:completed_at].nil?
                @task.undo_complete!
                r.halt 204
              end
            end

            r.is do
              r.patch do
                begin
                  body = JSON.parse(r.body.read)
                rescue JSON::ParserError
                  r.halt 422
                end

                updates = {}
                result = {}

                if body.key?("due_date")
                  r.halt 422 unless @task[:completed_at].nil?
                  begin
                    due_date = Date.parse(body["due_date"].to_s)
                  rescue Date::Error
                    r.halt 422
                  end
                  updates[:due_date] = due_date
                  result["due_date"] = due_date.to_s
                end

                if body.key?("note")
                  r.halt 422 if @task[:completed_at].nil?
                  note = body["note"].to_s.strip
                  updates[:note] = note.empty? ? nil : note
                  result["note"] = note
                end

                if body.key?("completed_at")
                  r.halt 422 if @task[:completed_at].nil?
                  begin
                    completed_date = Date.parse(body["completed_at"].to_s)
                  rescue Date::Error
                    r.halt 422
                  end
                  updates[:completed_at] = Time.new(completed_date.year, completed_date.month, completed_date.day)
                  result["completed_at"] = completed_date.to_s
                end

                unless updates.empty?
                  DB.transaction do
                    Task.where(id: task_id).update(updates)

                    if completed_date
                      latest = @series.completed_tasks.first
                      if latest && latest[:id] == @task[:id]
                        active = @series.active_task
                        active.update(due_date: @series.next_due_date(completed_date)) if active
                      end
                    end
                  end
                end

                response["content-type"] = "application/json"
                result.to_json
              end
            end
          end
        end
      end
    end
  end
end
