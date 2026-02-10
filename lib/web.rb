# frozen_string_literal: true

require "roda"

require_relative "models"
require_relative "views/home"

class Web < Roda
  plugin :halt
  plugin :static, %w[ /css /js ]

  def current_user
    login = env["HTTP_TAILSCALE_USER_LOGIN"]
    return unless login

    name = env["HTTP_TAILSCALE_USER_NAME"]
    User.upsert(login: login, name: name)
  end

  route do |r|
    r.halt 403 unless current_user

    r.root do
      tasks = Task.active.for_user(current_user).by_due_date.all
      Views::Home.new(current_user:, tasks:).call
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
