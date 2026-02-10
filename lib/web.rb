# frozen_string_literal: true

require "roda"

require_relative "views/series/new"

class Web < Roda
  plugin :halt
  plugin :static, %w[ /css /js ]

  def current_user
    login = env["HTTP_TAILSCALE_USER_LOGIN"]
    return unless login

    {
      login: login,
      name: env["HTTP_TAILSCALE_USER_NAME"],
    }
  end

  route do |r|
    r.halt 403 unless current_user

    r.root do
      Views::Series::New.new(current_user:).call
    end
  end
end
