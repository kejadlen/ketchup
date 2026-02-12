# frozen_string_literal: true

require "json"
require "roda"

require_relative "models"
require_relative "views/home"

class Web < Roda
  plugin :halt
  plugin :static, %w[ /css /js ]
  plugin :all_verbs

  def current_user
    login = env["HTTP_TAILSCALE_USER_LOGIN"]
    return unless login

    name = env["HTTP_TAILSCALE_USER_NAME"]
    User.find_or_create(login: login) { |u| u.name = name }
  end

  route do |r|
    r.halt 403 unless current_user

    r.root do
      all_tasks = Task.active.for_user(current_user).all
      overdue, upcoming = all_tasks.partition { |t| t.urgency > 0 }

      overdue.sort_by! { |t| -t.urgency }
      upcoming.sort_by! { |t| t[:due_date] }

      Views::Home.new(current_user:, overdue:, upcoming:).call
    end

    r.on "tasks", Integer do |task_id|
      r.post "complete" do
        task = Task.active.for_user(current_user).where(Sequel[:tasks][:id] => task_id).first
        r.halt 404 unless task
        task.complete!

        new_task = task.series.active_task
        response["content-type"] = "application/json"
        { series_id: task[:series_id], task: { id: new_task.id, due_date: new_task.due_date.to_s } }.to_json
      end

      r.patch "note" do
        task = Task.join(:series, id: :series_id)
          .where(Sequel[:series][:user_id] => current_user.id)
          .where(Sequel[:tasks][:id] => task_id)
          .select_all(:tasks)
          .first
        r.halt 404 unless task
        r.halt 422 if task[:completed_at].nil?

        note = r.params["note"].to_s.strip
        Task.where(id: task_id).update(note: note.empty? ? nil : note)

        response["content-type"] = "application/json"
        { note: note }.to_json
      end
    end

    r.on "series", Integer do |series_id|
      series = Series.where(id: series_id, user_id: current_user.id).first
      r.halt 404 unless series

      r.get "completed" do
        completed = series.tasks_dataset
          .exclude(completed_at: nil)
          .order(Sequel.desc(:completed_at))
          .select(:id, :due_date, :completed_at, :note)
          .all
          .map { |t| { id: t[:id], due_date: t[:due_date].to_s, completed_at: t[:completed_at].strftime("%Y-%m-%d"), note: t[:note] } }

        response["content-type"] = "application/json"
        completed.to_json
      end
    end

    r.on "series" do
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

        Series.create_with_first_task(
          user: current_user,
          note: note,
          interval_unit: interval_unit,
          interval_count: interval_count,
          first_due_date: due_date
        )

        r.redirect "/"
      end
    end
  end
end
