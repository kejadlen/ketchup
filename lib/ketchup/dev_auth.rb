# frozen_string_literal: true

module Ketchup
  class DevAuth
    def initialize(app, default_user)
      @app = app
      @login = default_user.login
      @name = default_user.name
    end

    def call(env)
      unless env["HTTP_TAILSCALE_USER_LOGIN"]
        env["HTTP_TAILSCALE_USER_LOGIN"] = @login
        env["HTTP_TAILSCALE_USER_NAME"] = @name
      end
      @app.call(env)
    end
  end
end
