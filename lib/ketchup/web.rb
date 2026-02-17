# frozen_string_literal: true

require "json"
require "roda"

require_relative "models"
require_relative "views/dashboard"
require_relative "views/series/new"

class Web < Roda
  plugin :halt
  plugin :static, %w[ /css /js /favicon.svg ]
  plugin :all_verbs
  plugin :sessions, secret: CONFIG.session_secret
  plugin :route_csrf, csrf_failure: :empty_403, check_request_methods: %w[POST]
  plugin :error_handler do |e|
    raise e unless e.is_a?(Sequel::NoMatchingRow)

    response.status = 404
    ""
  end

  def current_user
    rack_header = "HTTP_#{CONFIG.auth_header.upcase.tr("-", "_")}"
    login = env[rack_header]
    return unless login

    User.find_or_create(login: login) { |u| u.name = login }
  end

  route do |r|
    @user = current_user
    r.halt 403 unless @user

    check_csrf!

    r.root do
      Views::Dashboard.new(current_user: @user, csrf: method(:csrf_token)).call
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

        r.is do
          r.get do
            Views::Dashboard.new(current_user: @user, series: @series, csrf: method(:csrf_token)).call
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

            if r.params.key?("due_date")
              begin
                due_date = Date.parse(r.params["due_date"].to_s)
              rescue Date::Error
                r.halt 422
              end
            end

            DB.transaction do
              @series.update(updates) unless updates.empty?
              if due_date
                active = @series.active_task
                active.update(due_date: due_date) if active
              end
            end

            response["content-type"] = "application/json"
            result = updates.transform_keys(&:to_s)
            result["due_date"] = due_date.to_s if due_date
            result.to_json
          end
        end

        r.on "tasks", Integer do |task_id|
          @task = @series.tasks_dataset.where(id: task_id).sole

          r.post "complete" do
            r.halt 422 unless @task[:completed_at].nil?
            @task.complete!(today: Date.today)

            r.redirect "/series/#{series_id}"
          end

          r.patch "note" do
            r.halt 422 if @task[:completed_at].nil?

            note = r.params["note"].to_s.strip
            Task.where(id: task_id).update(note: note.empty? ? nil : note)

            response["content-type"] = "application/json"
            { note: note }.to_json
          end
        end
      end
    end
  end
end
