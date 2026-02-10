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

  route do |r|
    r.halt 403 unless current_user

    r.root do
      Views::Series::New.new(current_user:).call
    end
  end
end
