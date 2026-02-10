# frozen_string_literal: true

require "roda"

require_relative "db"
require_relative "views/series/new"

class Web < Roda
  plugin :halt
  plugin :static, %w[ /css /js ]

  def current_user
    login = env["HTTP_TAILSCALE_USER_LOGIN"]
    return unless login

    name = env["HTTP_TAILSCALE_USER_NAME"]
    now = Time.now

    DB[:users]
      .insert_conflict(target: :login, update: { name: name, updated_at: now })
      .insert(login: login, name: name, created_at: now, updated_at: now)

    DB[:users].first(login: login)
  end

  INTERVAL_UNITS = %w[day week month quarter year].freeze

  route do |r|
    r.halt 403 unless current_user

    r.root do
      Views::Series::New.new(current_user:).call
    end

    r.on "series" do
      r.post do
        note = r.params["note"].to_s.strip
        interval_unit = r.params["interval_unit"].to_s
        interval_count = r.params["interval_count"].to_i
        first_due_date = r.params["first_due_date"].to_s

        r.halt 422 if note.empty?
        r.halt 422 unless INTERVAL_UNITS.include?(interval_unit)
        r.halt 422 unless interval_count >= 1

        begin
          due_date = Date.parse(first_due_date)
        rescue Date::Error
          r.halt 422
        end

        now = Time.now
        DB.transaction do
          series_id = DB[:series].insert(
            user_id: current_user[:id],
            note: note,
            interval_unit: interval_unit,
            interval_count: interval_count,
            created_at: now,
            updated_at: now
          )

          DB[:tasks].insert(
            series_id: series_id,
            due_date: due_date,
            created_at: now,
            updated_at: now
          )
        end

        r.redirect "/"
      end
    end
  end
end
